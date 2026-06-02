import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../data/native_sms_client.dart';
import '../data/template_storage.dart';
import '../data/contact_storage.dart';
import '../../shared/shared_models.dart';
import '../../shared/security_service.dart';

class HttpRouter {
  final NativeSmsClient _smsClient;
  final TemplateStorage _templateStorage;
  final ContactStorage _contactStorage = ContactStorage();
  SecurityService _security;
  final String _webRootPath;
  final List<WebSocketChannel> _sockets = [];

  // Индекс файлов для быстрого поиска и обхода проблем с путями Windows
  final Map<String, File> _fileIndex = {};

  bool _isSecured = false;
  String? _currentSessionId;

  DateTime _lastActivity = DateTime.now();
  void Function()? onIdle;

  HttpRouter(this._smsClient, this._templateStorage, this._security, this._webRootPath, {this.onIdle}) {
    _smsClient.onSmsReceived.listen((msg) {
      _lastActivity = DateTime.now();
      broadcast(msg);
    });
    
    // Периодическая проверка простоя (например, каждые 5 минут)
    Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_sockets.isEmpty && 
          DateTime.now().difference(_lastActivity) > const Duration(minutes: 30)) {
        onIdle?.call();
      }
    });
  }

  void _trackActivity() => _lastActivity = DateTime.now();

  // Сканируем файлы один раз при старте
  Future<void> initialize() async {
    _fileIndex.clear();
    final dir = Directory(_webRootPath);
    if (!await dir.exists()) return;

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          // Получаем путь относительно папки web_root и нормализуем слеши
          final relPath = entity.path
              .substring(_webRootPath.length + 1)
              .replaceAll('\\', '/');

          final fileName = entity.path.split(Platform.pathSeparator).last;

          _fileIndex[relPath] = entity;
          // Позволяет найти файл просто по имени (например, для шрифтов)
          _fileIndex.putIfAbsent(fileName, () => entity);
        }
      }
      stdout.writeln("Server indexed ${_fileIndex.length} files.");
    } catch (e) {
      stdout.writeln("Indexing error: $e");
    }
  }

  void updateSecurity(String password, String sessionId) {
    _security = SecurityService(password);
    _currentSessionId = sessionId;
    _isSecured = true;
  }

  void broadcast(SmsMessageDto msg) {
    if (_sockets.isEmpty) return;
    try {
      final encrypted = _security.encrypt({
        'type': 'NEW_SMS',
        'data': msg.toJson(),
      });
      for (var ws in _sockets) {
        try {
          ws.sink.add(encrypted);
        } catch (_) {}
      }
    } catch (e) {
      stdout.writeln("Broadcast error: $e");
    }
  }

  Handler get handler {
    final router = Router();

    // API Routes
    router.get(
      '/api/ping',
      (Request req) {
        _trackActivity();
        return Response.ok(
          jsonEncode({
            'status': 'alive',
            'secured': _isSecured,
            'session_id': _currentSessionId,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      },
    );

    router.get('/api/sims', (Request req) async {
      _trackActivity();
      final sims = await _smsClient.getSimCards();
      return _encryptedRes(sims.map((e) => e.toJson()).toList());
    });

    router.get('/api/messages', (Request req) async {
      _trackActivity();
      final params = req.url.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '') ?? 50;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;
      final address = params['address'];

      final msgs = await _smsClient.getMessages(
        limit: limit,
        offset: offset,
        address: address,
      );
      return _encryptedRes(msgs.map((e) => e.toJson()).toList());
    });

    router.get('/api/threads', (Request req) async {
      _trackActivity();
      final params = req.url.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '') ?? 50;
      final threads = await _smsClient.getThreads(limit: limit);
      return _encryptedRes(threads.map((e) => e.toJson()).toList());
    });

    // === Templates API ===
    router.get('/api/templates', (Request req) async {
      _trackActivity();
      final templates = await _templateStorage.loadTemplates();
      return _encryptedRes(templates.map((e) => e.toJson()).toList());
    });

    router.post('/api/templates', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security.decrypt(payload);
      final template = SmsTemplateDto.fromJson(data);
      await _templateStorage.addOrUpdateTemplate(template);
      return _encryptedRes({'status': 'ok'});
    });

    router.delete('/api/templates', (Request req) async {
      _trackActivity();
      final params = req.url.queryParameters;
      final id = params['id'];
      if (id != null) {
        await _templateStorage.deleteTemplate(id);
      }
      return _encryptedRes({'status': 'ok'});
    });

    // === Contacts API ===
    router.get('/api/contacts', (Request req) async {
      _trackActivity();
      final contacts = await _contactStorage.loadContacts();
      return _encryptedRes(contacts.map((e) => e.toJson()).toList());
    });

    router.post('/api/contacts', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security.decrypt(payload);
      final contact = ContactDto.fromJson(data);
      await _contactStorage.addOrUpdateContact(contact);
      return _encryptedRes({'status': 'ok'});
    });

    router.delete('/api/contacts', (Request req) async {
      _trackActivity();
      final params = req.url.queryParameters;
      final phone = params['phone'];
      if (phone != null) {
        await _contactStorage.deleteContact(phone);
      }
      return _encryptedRes({'status': 'ok'});
    });

    router.post('/api/send', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security.decrypt(payload);

      final address = data['address'];
      final body = data['body'];
      final subId = data['subId'] ?? 0;

      // 1. Отправляем физическое SMS через нативный клиент
      await _smsClient.sendSms(address, body, subId);

      // 2. Создаем объект сообщения для обновления UI в вебе
      final newMsg = SmsMessageDto(
        address: address,
        body: body,
        date: DateTime.now().millisecondsSinceEpoch,
        isSent: true, // Это исходящее
        subId: subId,
      );

      // 3. Рассылаем через WebSocket всем подключенным клиентам
      broadcast(newMsg);

      return _encryptedRes({'status': 'ok'});
    });

    router.get('/ws', (Request req) {
      _trackActivity();
      return webSocketHandler((WebSocketChannel ws, _) {
        _sockets.add(ws);
        ws.stream.listen((_) => _trackActivity(), onDone: () => _sockets.remove(ws));
      })(req);
    });

    // Static Files Catch-all
    router.get('/<ignored|.*>', _handleStatic);

    // Pipeline с исправленным Middleware
    return const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);
  }

  Future<Response> _handleStatic(Request req) async {
    _trackActivity();
    String path = req.url.path;
    if (path.startsWith('/')) path = path.substring(1);
    path = Uri.decodeComponent(path);
    if (path.isEmpty) path = 'index.html';

    // Ищем в индексе
    File? file = _fileIndex[path] ?? _fileIndex[path.split('/').last];

    if (file != null && await file.exists()) {
      final length = await file.length();
      final name = file.path.toLowerCase();
      
      // Более расширенный MIME-маппинг
      final mime = _getMimeType(name);

      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': mime,
          'Content-Length': length.toString(),
          'Cache-Control': 'public, max-age=3600', // Кэшируем на час
        },
      );
    }

    // Если файл не найден, но есть index.html (для SPA)
    if (_fileIndex.containsKey('index.html')) {
      final indexFile = _fileIndex['index.html']!;
      return Response.ok(
        indexFile.openRead(),
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Content-Length': (await indexFile.length()).toString(),
        },
      );
    }

    return Response.notFound('Not found');
  }

  String _getMimeType(String fileName) {
    if (fileName.endsWith('.html')) return 'text/html; charset=utf-8';
    if (fileName.endsWith('.js')) return 'application/javascript';
    if (fileName.endsWith('.css')) return 'text/css';
    if (fileName.endsWith('.json')) return 'application/json';
    if (fileName.endsWith('.png')) return 'image/png';
    if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) return 'image/jpeg';
    if (fileName.endsWith('.svg')) return 'image/svg+xml';
    if (fileName.endsWith('.wasm')) return 'application/wasm';
    if (fileName.endsWith('.ttf')) return 'font/ttf';
    if (fileName.endsWith('.otf')) return 'font/otf';
    if (fileName.endsWith('.woff')) return 'font/woff';
    if (fileName.endsWith('.woff2')) return 'font/woff2';
    return 'application/octet-stream';
  }

  Response _encryptedRes(dynamic data) => Response.ok(
    _security.encrypt(data),
    headers: {'Content-Type': 'text/plain'},
  );

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Private-Network': 'true',
  };

  // ИСПРАВЛЕННЫЙ Middleware
  static Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }
}
