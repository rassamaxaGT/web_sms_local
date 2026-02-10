import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:nsd/nsd.dart';
import '../data/native_sms_client.dart';
import 'http_router.dart';
import '../../shared/security_service.dart';

class ServerManager {
  HttpServer? _server;
  final NativeSmsClient _smsClient = NativeSmsClient();
  HttpRouter? _router;
  Registration? _registration;

  // Поля для сохранения состояния между открытиями UI
  String? _currentUrl;
  bool _isSecured = false;

  NativeSmsClient get smsClient => _smsClient;

  // Геттеры для проверки состояния из виджетов
  bool get isRunning => _server != null;
  String? get currentUrl => _currentUrl;
  bool get isSecured => _isSecured;

  Future<String> start() async {
    // Если сервер уже запущен, просто возвращаем текущий URL
    if (_server != null) return _currentUrl!;

    final staticPath = await _prepareWebAssets();

    // Начальный пароль для ожидания сканирования QR
    final security = SecurityService("waiting_for_qr");
    _router = HttpRouter(_smsClient, security, staticPath);

    // Индексируем файлы (наш фикс для иконок)
    await _router!.initialize();

    String ip = '0.0.0.0';
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.')) {
            ip = addr.address;
            break;
          }
        }
      }
    } catch (_) {}

    _server = await shelf_io.serve(_router!.handler, ip, 8080, shared: true);
    _currentUrl = 'http://$ip:${_server!.port}';
    _isSecured = false; // Сбрасываем статус защиты при новом запуске

    await _registerMdnsService();

    return _currentUrl!;
  }

  Future<void> _registerMdnsService() async {
    try {
      const String serviceName = 'sms-host';
      _registration = await register(
        const Service(name: serviceName, type: '_http._tcp', port: 8080),
      );
    } catch (e) {
      stdout.writeln("mDNS registration error: $e");
    }
  }

  Future<void> _unregisterMdns() async {
    if (_registration != null) {
      try {
        await unregister(_registration!);
        _registration = null;
      } catch (e) {
        stdout.writeln("mDNS unregistration error: $e");
      }
    }
  }

  Future<String> _prepareWebAssets() async {
    final docDir = await getApplicationDocumentsDirectory();
    final webDir = Directory('${docDir.path}/web_root');

    if (await webDir.exists()) {
      await webDir.delete(recursive: true);
    }
    await webDir.create(recursive: true);

    try {
      final zipData = await rootBundle.load('assets/web.zip');
      final bytes = zipData.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        // Фикс путей Windows для Android
        final fixedName = file.name.replaceAll('\\', '/');
        final fullPath = '${webDir.path}/$fixedName';

        if (file.isFile) {
          final outFile = File(fullPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(fullPath).create(recursive: true);
        }
      }
      stdout.writeln("Assets unpacked successfully.");
    } catch (e) {
      stdout.writeln("Unzip error: $e");
    }
    return webDir.path;
  }

  void updatePassword(String newPassword, String sessionId) {
    _router?.updateSecurity(newPassword, sessionId);
    _isSecured = true; // Запоминаем, что QR успешно отсканирован
  }

  void stop() {
    _unregisterMdns();
    _server?.close();
    _server = null;
    _currentUrl = null;
    _isSecured = false;
  }
}
