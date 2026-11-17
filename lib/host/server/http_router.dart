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
import '../data/campaign_storage.dart';
import '../service/broadcast_engine.dart';
import '../../shared/shared_models.dart';
import '../../shared/contractor_models.dart';
import '../../client/data/tbank_contractor_service.dart';
import '../../shared/security_service.dart';
import '../../shared/app_logger.dart';
import '../../client/utils/recipient_importer.dart';
import 'package:flutter/services.dart';

class HttpRouter {
  final NativeSmsClient _smsClient;
  final TemplateStorage _templateStorage;
  final ContactStorage _contactStorage = ContactStorage();
  final CampaignStorage _campaignStorage;
  final BroadcastEngine _broadcastEngine;
  SecurityService? _security;
  final String _webRootPath;
  final List<WebSocketChannel> _sockets = [];

  // Индекс файлов для быстрого поиска и обхода проблем с путями Windows
  final Map<String, File> _fileIndex = {};

  bool _isSecured = false;
  String? _currentSessionId;

  DateTime _lastActivity = DateTime.now();
  void Function()? onIdle;
  StreamSubscription<SmsMessageDto>? _smsSubscription;
  Timer? _idleTimer;

  HttpRouter(
    this._smsClient,
    this._templateStorage,
    this._campaignStorage,
    this._broadcastEngine,
    this._security,
    this._webRootPath, {
    this.onIdle,
  }) {
    _smsSubscription = _smsClient.onSmsReceived.listen((msg) {
      _lastActivity = DateTime.now();
      broadcast(msg);
    });

    _smsClient.onCallStateChanged.listen((event) {
      _lastActivity = DateTime.now();
      broadcastCustom('CALL_STATE_CHANGED', event);
    });

    _smsClient.onDeviceStateChanged.listen((volumeDto) {
      _lastActivity = DateTime.now();
      broadcastCustom('DEVICE_VOLUME_CHANGED', volumeDto.toJson());
    });

    _broadcastEngine.onEvent = (type, data) {
      _lastActivity = DateTime.now();
      broadcastCustom(type, data);
    };
    
    // Периодическая проверка простоя (например, каждые 5 минут)
    _idleTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_sockets.isEmpty && 
          DateTime.now().difference(_lastActivity) > const Duration(minutes: 30)) {
        onIdle?.call();
      }
    });
  }

  Future<void> dispose() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _smsSubscription?.cancel();
    _smsSubscription = null;
    for (final ws in List<WebSocketChannel>.from(_sockets)) {
      try {
        await ws.sink.close();
      } catch (_) {}
    }
    _sockets.clear();
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
    broadcastCustom('NEW_SMS', msg.toJson());
  }

  void broadcastCustom(String type, dynamic data) {
    if (!_isSecured || _security == null || _sockets.isEmpty) return;
    try {
      final encrypted = _security!.encrypt({
        'type': type,
        'data': data,
      });
      for (var ws in _sockets) {
        try {
          ws.sink.add(encrypted);
        } catch (_) {}
      }
    } catch (e) {
      stdout.writeln("Broadcast error ($type): $e");
    }
  }

  bool _isAuthorized(Request req, {bool allowQueryToken = false}) {
    if (!_isSecured || _security == null) return false;
    final authHeader = req.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      final token = authHeader.substring(7).trim();
      if (_security!.verifyAuthToken(token)) return true;
    }
    if (allowQueryToken) {
      final queryToken = req.url.queryParameters['token'];
      if (_security!.verifyAuthToken(queryToken)) return true;
    }
    return false;
  }

  Response _unauthorizedResponse() => Response(
    401,
    body: jsonEncode({'error': 'Unauthorized'}),
    headers: {'Content-Type': 'application/json'},
  );

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
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      final sims = await _smsClient.getSimCards();
      return _encryptedRes(sims.map((e) => e.toJson()).toList());
    });

    router.get('/api/messages', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
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
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      final params = req.url.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '') ?? 50;
      final threads = await _smsClient.getThreads(limit: limit);
      return _encryptedRes(threads.map((e) => e.toJson()).toList());
    });

    // === Templates API ===
    router.get('/api/templates', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      final templates = await _templateStorage.loadTemplates();
      return _encryptedRes(templates.map((e) => e.toJson()).toList());
    });

    router.post('/api/templates', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      try {
        final payload = await req.readAsString();
        final data = _security!.decrypt(payload);
        if (data is! Map<String, dynamic>) {
          return Response(400, body: 'Invalid template payload');
        }
        final template = SmsTemplateDto.fromJson(data);
        await _templateStorage.addOrUpdateTemplate(template);
        return _encryptedRes({'status': 'ok'});
      } catch (e) {
        return Response(400, body: 'Failed to save template: $e');
      }
    });

    router.delete('/api/templates', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
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
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      final contacts = await _contactStorage.loadContacts();
      return _encryptedRes(contacts.map((e) => e.toJson()).toList());
    });

    router.post('/api/contacts', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      try {
        final payload = await req.readAsString();
        final data = _security!.decrypt(payload);
        if (data is! Map<String, dynamic>) {
          return Response(400, body: 'Invalid contact payload');
        }
        final contact = ContactDto.fromJson(data);
        await _contactStorage.addOrUpdateContact(contact);
        return _encryptedRes({'status': 'ok'});
      } catch (e) {
        return Response(400, body: 'Failed to save contact: $e');
      }
    });

    router.delete('/api/contacts', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      final params = req.url.queryParameters;
      final phone = params['phone'];
      if (phone != null) {
        await _contactStorage.deleteContact(phone);
      }
      return _encryptedRes({'status': 'ok'});
    });

    // === Campaigns (Broadcast) API ===
    router.get('/api/campaigns', (Request req) async {
      _trackActivity();
      final campaigns = await _campaignStorage.loadCampaigns(summaryOnly: false);
      return _encryptedRes(campaigns.map((e) => e.toJson(includeItems: true)).toList());
    });

    router.get('/api/campaigns/<id>', (Request req, String id) async {
      _trackActivity();
      final campaign = await _campaignStorage.getCampaign(id);
      if (campaign == null) return Response.notFound('Campaign not found');
      return _encryptedRes(campaign.toJson(includeItems: true));
    });

    router.post('/api/campaigns', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security!.decrypt(payload);
      final campaign = CampaignDto.fromJson(Map<String, dynamic>.from(data));
      await _campaignStorage.saveCampaign(campaign);
      return _encryptedRes({'status': 'ok', 'id': campaign.id});
    });

    router.post('/api/campaigns/<id>/start', (Request req, String id) async {
      _trackActivity();
      await _broadcastEngine.startCampaign(id);
      return _encryptedRes({'status': 'ok'});
    });

    router.post('/api/campaigns/<id>/pause', (Request req, String id) async {
      _trackActivity();
      await _broadcastEngine.pauseCampaign(id);
      return _encryptedRes({'status': 'ok'});
    });

    router.post('/api/campaigns/<id>/stop', (Request req, String id) async {
      _trackActivity();
      await _broadcastEngine.stopCampaign(id);
      return _encryptedRes({'status': 'ok'});
    });

    router.post('/api/campaigns/<id>/retry-failed', (Request req, String id) async {
      _trackActivity();
      await _broadcastEngine.retryFailed(id);
      return _encryptedRes({'status': 'ok'});
    });

    router.delete('/api/campaigns/<id>', (Request req, String id) async {
      _trackActivity();
      if (_broadcastEngine.activeCampaignId == id) {
        await _broadcastEngine.stopCampaign(id);
      }
      await _campaignStorage.deleteCampaign(id);
      return _encryptedRes({'status': 'ok'});
    });

    // === Contractor API (Proxy to avoid browser CORS) ===
    router.get('/api/contractor/search', (Request req) async {
      _trackActivity();
      final query = req.url.queryParameters['query'] ?? '';
      final service = TBankContractorService();
      final results = await service.search(query);
      return _encryptedRes(results.map((e) => e.toJson()).toList());
    });

    router.post('/api/contractor/okved', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security!.decrypt(payload);
      final contractor = ContractorDto.fromJson(Map<String, dynamic>.from(data));
      final service = TBankContractorService();
      final enriched = await service.fetchOkvedDetails(contractor);
      return _encryptedRes(enriched.toJson());
    });

    router.post('/api/send', (Request req) async {
      if (!_isAuthorized(req)) return _unauthorizedResponse();
      _trackActivity();
      try {
        final payload = await req.readAsString();
        final data = _security!.decrypt(payload);
        if (data is! Map<String, dynamic>) {
          return Response(400, body: 'Invalid send payload');
        }

        final address = data['address'];
        final body = data['body'];
        final subId = (data['subId'] as num?)?.toInt() ?? 0;
        if (address is! String || address.isEmpty || body is! String) {
          return Response(400, body: 'Missing address or body');
        }

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
      } catch (e) {
        return Response.internalServerError(body: 'Send failed: $e');
      }
    });

    router.post('/api/call', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security!.decrypt(payload);

      final phone = data['phone'];
      final subId = data['subId'] ?? -1;

      if (phone != null) {
        const platform = MethodChannel('com.example.sms_host/methods');
        try {
          await platform.invokeMethod('makePhoneCall', {
            'phoneNumber': phone,
            'subscriptionId': subId,
          });
          return _encryptedRes({'status': 'ok'});
        } catch (e) {
          return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
            headers: {'content-type': 'application/json'},
          );
        }
      }
      return Response.badRequest(body: 'Missing phone');
    });

    router.post('/api/call/hangup', (Request req) async {
      _trackActivity();
      try {
        final success = await _smsClient.endPhoneCall();
        return _encryptedRes({'status': 'ok', 'terminated': success});
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.get('/api/calls', (Request req) async {
      _trackActivity();
      final params = req.url.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '') ?? 200;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;
      final calls = await _smsClient.getCallLogs(limit: limit, offset: offset);

      // Only add name from CRM contact if Android system call log did not specify a name
      try {
        final contacts = await _contactStorage.loadContacts();
        final enriched = calls.map((call) {
          if (call.name == null || call.name!.trim().isEmpty) {
            final matched = contacts.firstWhere(
              (c) => RecipientImporter.isSamePhone(c.phone, call.number) && c.name.trim().isNotEmpty,
              orElse: () => ContactDto(phone: '', name: '', notes: ''),
            );
            if (matched.name.trim().isNotEmpty) {
              return CallLogEntryDto(
                id: call.id,
                number: call.number,
                name: matched.name.trim(),
                date: call.date,
                durationSeconds: call.durationSeconds,
                direction: call.direction,
                status: call.status,
                comment: call.comment,
              );
            }
          }
          return call;
        }).toList();
        return _encryptedRes(enriched.map((e) => e.toJson()).toList());
      } catch (e) {
        return _encryptedRes(calls.map((e) => e.toJson()).toList());
      }
    });

    // === Device Volume API ===
    router.get('/api/device/volume', (Request req) async {
      _trackActivity();
      final volumeDto = await _smsClient.getDeviceVolume();
      return _encryptedRes(volumeDto.toJson());
    });

    router.post('/api/device/volume', (Request req) async {
      _trackActivity();
      final payload = await req.readAsString();
      final data = _security!.decrypt(payload);
      final stream = data['stream']?.toString() ?? 'ring';

      DeviceVolumeDto updated;
      if (data['direction'] != null) {
        final direction = data['direction'].toString();
        updated = await _smsClient.adjustDeviceVolume(stream: stream, direction: direction);
      } else {
        final volume = (data['volume'] as num?)?.toInt() ?? 0;
        updated = await _smsClient.setDeviceVolume(stream: stream, volume: volume);
      }
      return _encryptedRes(updated.toJson());
    });

    router.get('/api/logs', (Request req) async {
      _trackActivity();
      final logs = await AppLogger.getFullLogText();
      return Response.ok(
        logs,
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'no-cache',
        },
      );
    });

    router.get('/ws', (Request req) {
      if (!_isAuthorized(req, allowQueryToken: true)) {
        return _unauthorizedResponse();
      }
      _trackActivity();
      return webSocketHandler((WebSocketChannel ws, _) {
        _sockets.add(ws);
        _smsClient.getDeviceVolume().then((vol) {
          if (!_isSecured || _security == null) return;
          try {
            final encrypted = _security!.encrypt({
              'type': 'DEVICE_VOLUME_CHANGED',
              'data': vol.toJson(),
            });
            ws.sink.add(encrypted);
          } catch (_) {}
        });
        ws.stream.listen(
          (_) => _trackActivity(),
          onDone: () => _sockets.remove(ws),
          onError: (_) => _sockets.remove(ws),
        );
      })(req);
    });

    // Static Files Catch-all
    router.get('/<ignored|.*>', _handleStatic);

    // Pipeline с исправленным Middleware
    return Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);
  }

  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final path = request.url.path;
        if (path.startsWith('api/') && path != 'api/ping') {
          if (!_isAuthorized(request)) {
            return _unauthorizedResponse();
          }
        }
        return innerHandler(request);
      };
    };
  }

  Future<Response> _handleStatic(Request req) async {
    _trackActivity();
    String path = req.url.path;
    if (path.startsWith('/')) path = path.substring(1);
    try {
      path = Uri.decodeComponent(path);
    } catch (_) {
      return Response(400, body: 'Invalid URL encoding');
    }
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
    _security!.encrypt(data),
    headers: {'Content-Type': 'text/plain'},
  );

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
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
