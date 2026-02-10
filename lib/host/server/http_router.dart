import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../data/native_sms_client.dart';
import '../../shared/shared_models.dart';
import '../../shared/security_service.dart';

class HttpRouter {
  final NativeSmsClient _smsClient;
  SecurityService _security;
  final String _webRootPath;
  final List<WebSocketChannel> _sockets = [];

  // Индекс файлов для быстрого поиска и обхода проблем с путями Windows
  final Map<String, File> _fileIndex = {};

  bool _isSecured = false;
  String? _currentSessionId;

  HttpRouter(this._smsClient, this._security, this._webRootPath) {
    _smsClient.onSmsReceived.listen(broadcast);
  }

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
      (Request req) => Response.ok(
        jsonEncode({
          'status': 'alive',
          'secured': _isSecured,
          'session_id': _currentSessionId,
        }),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    router.get('/api/sims', (Request req) async {
      final sims = await _smsClient.getSimCards();
      return _encryptedRes(sims.map((e) => e.toJson()).toList());
    });

    router.get('/api/messages', (Request req) async {
      final msgs = await _smsClient.getFullHistory();
      return _encryptedRes(msgs.map((e) => e.toJson()).toList());
    });

    router.post('/api/send', (Request req) async {
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
      return webSocketHandler((WebSocketChannel ws, _) {
        _sockets.add(ws);
        ws.stream.listen((_) {}, onDone: () => _sockets.remove(ws));
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
    String path = req.url.path;
    if (path.startsWith('/')) path = path.substring(1);
    path = Uri.decodeComponent(path);
    if (path.isEmpty) path = 'index.html';

    // Ищем в индексе (сначала по полному пути, потом по имени файла)
    File? file = _fileIndex[path] ?? _fileIndex[path.split('/').last];

    if (file != null && await file.exists()) {
      final bytes = await file.readAsBytes();
      final name = file.path.toLowerCase();
      String mime = 'text/plain';

      if (name.endsWith('.html')) {
        mime = 'text/html; charset=utf-8';
      } else if (name.endsWith('.js')) {
        mime = 'application/javascript';
      } else if (name.endsWith('.css')) {
        mime = 'text/css';
      } else if (name.endsWith('.json')) {
        mime = 'application/json';
      } else if (name.endsWith('.otf')) {
        mime = 'font/otf';
      } else if (name.endsWith('.ttf')) {
        mime = 'font/ttf';
      } else if (name.endsWith('.wasm')) {
        mime = 'application/wasm';
      }

      return Response.ok(bytes, headers: {'Content-Type': mime});
    }

    // Если файл не найден, но есть index.html (для SPA)
    if (_fileIndex.containsKey('index.html')) {
      final bytes = await _fileIndex['index.html']!.readAsBytes();
      return Response.ok(bytes, headers: {'Content-Type': 'text/html'});
    }

    return Response.notFound('Not found');
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
