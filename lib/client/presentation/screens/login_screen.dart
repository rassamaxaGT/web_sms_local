import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import '../../logic/providers.dart';
import '../../logic/network_scanner.dart';
import 'home_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _status = "Инициализация системы...";
  String? _foundHost;
  late final String _password;
  late final String _sessionId;
  bool _isScanning = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _password = const Uuid().v4().substring(0, 8);
    _sessionId = const Uuid().v4().substring(0, 6);
    _checkEnvironment();
  }

  void _checkEnvironment() {
    if (!kIsWeb) {
      _startScan();
      return;
    }

    final location = web.window.location;
    final hostname = location.hostname;
    final protocol = location.protocol;
    final host = location.host;

    if (hostname.startsWith("192.168.") || hostname.startsWith("10.")) {
      final hostUrl = "$protocol//$host";
      setState(() {
        _foundHost = hostUrl;
        _isScanning = false;
        _status = "Сервер найден. Сканируйте QR для входа.";
      });
      _startPollingForReadiness(hostUrl);
    } else {
      _startScan();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _foundHost = null;
      _status = "Поиск телефона в локальной сети...";
    });

    final host = await NetworkScanner.findHostIP();

    if (mounted) {
      if (host != null) {
        setState(() {
          _foundHost = host;
          _status = "Телефон обнаружен! Ожидание авторизации...";
          _isScanning = false;
        });
        _startPollingForReadiness(host);
      } else {
        setState(() {
          _status = "Телефон не найден. Убедитесь, что Wi-Fi включен.";
          _isScanning = false;
        });
      }
    }
  }

  void _startPollingForReadiness(String host) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final res = await http.get(Uri.parse('$host/api/ping'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['secured'] == true && data['session_id'] == _sessionId) {
            timer.cancel();
            _completePairing();
          }
        }
      } catch (_) {}
    });
  }

  void _completePairing() {
    if (_foundHost != null && mounted) {
      ref.read(serverUrlProvider.notifier).set(_foundHost);
      ref.read(passwordProvider.notifier).set(_password);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _showManualIpDialog() {
    final controller = TextEditingController(text: "192.168.");
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Ввести IP вручную"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "192.168.x.x",
            prefixIcon: Icon(Icons.lan),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                var fullUrl = ip;
                if (!fullUrl.startsWith('http')) fullUrl = "http://$fullUrl";
                if (!fullUrl.contains(':8080')) fullUrl = "$fullUrl:8080";
                _checkManualHost(fullUrl);
              }
            },
            child: const Text("Подключить"),
          ),
        ],
      ),
    );
  }

  Future<void> _checkManualHost(String host) async {
    setState(() {
      _isScanning = true;
      _status = "Проверка соединения с $host...";
    });

    try {
      final res = await http.get(Uri.parse('$host/api/ping')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _foundHost = host;
          _isScanning = false;
          _status = "Соединение установлено! Сканируйте QR.";
        });
        _startPollingForReadiness(host);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = "Не удалось подключиться к $host";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrData = jsonEncode({'pass': _password, 'id': _sessionId});

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.indigo.shade900, Colors.indigo.shade500],
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(40),
            constraints: const BoxConstraints(maxWidth: 450),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.message_rounded, size: 60, color: Colors.indigo),
                const SizedBox(height: 20),
                const Text(
                  "SMS Web Client",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
                const SizedBox(height: 30),
                if (_isScanning)
                  const CircularProgressIndicator()
                else if (_foundHost != null)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: QrImageView(
                          data: qrData,
                          size: 200.0,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Colors.indigo),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Colors.indigo),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text("Адрес: $_foundHost", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  )
                else
                  Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 80, color: Colors.grey),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Повторить поиск"),
                        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _showManualIpDialog,
                        icon: const Icon(Icons.edit),
                        label: const Text("Ввести IP вручную"),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}