import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../server/server_manager.dart';
import '../qr_scan_screen.dart';

class ServerControlPanel extends StatefulWidget {
  final ServerManager serverManager;
  const ServerControlPanel({super.key, required this.serverManager});

  @override
  State<ServerControlPanel> createState() => _ServerControlPanelState();
}

class _ServerControlPanelState extends State<ServerControlPanel> {
  String _status = "Готов к работе";
  String? _serverUrl;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    // СИНХРОНИЗАЦИЯ: Подхватываем реальное состояние из долгоживущего ServerManager
    _isRunning = widget.serverManager.isRunning;
    _serverUrl = widget.serverManager.currentUrl;

    if (_isRunning) {
      if (widget.serverManager.isSecured) {
        _status = "ЗАЩИЩЕНО И ПОДКЛЮЧЕНО";
      } else {
        _status = "Сервер активен";
      }
    }
  }

  Future<void> _startServer() async {
    setState(() => _status = "Запуск...");
    try {
      final service = FlutterBackgroundService();
      // Запускаем фоновый сервис Android, чтобы сервер не убила система
      if (!await service.isRunning()) await service.startService();

      final url = await widget.serverManager.start();
      setState(() {
        _isRunning = true;
        _serverUrl = url;
        _status = "Сервер активен";
      });
    } catch (e) {
      setState(() => _status = "Ошибка: $e");
    }
  }

  void _stopServer() {
    widget.serverManager.stop();
    FlutterBackgroundService().invoke("stopService");
    setState(() {
      _isRunning = false;
      _serverUrl = null;
      _status = "Сервер остановлен";
    });
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );

    if (result != null && result is Map) {
      widget.serverManager.updatePassword(result['pass'], result['id']);
      setState(() => _status = "ЗАЩИЩЕНО И ПОДКЛЮЧЕНО");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Сопряжение выполнено!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Полоска-индикатор для смахивания вниз
          Container(
            width: 40,
            height: 4,
            color: Colors.grey[300],
            margin: const EdgeInsets.only(bottom: 20),
          ),
          const Text(
            "Веб-синхронизация",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Блок с адресами сервера (показываем только если запущен)
          if (_serverUrl != null)
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Локальный адрес:",
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "http://sms-host.local:8080",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontSize: 16,
                        ),
                      ),
                      const Divider(),
                      Text(
                        "IP адрес: $_serverUrl",
                        style: TextStyle(
                          color: Colors.green[800],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),

          Text(
            _status,
            style: TextStyle(
              color: _status.contains("ЗАЩИЩЕНО")
                  ? Colors.green
                  : Colors.grey[600],
              fontWeight: _status.contains("ЗАЩИЩЕНО")
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 20),

          // Кнопки управления в зависимости от состояния
          if (!_isRunning)
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text("ЗАПУСТИТЬ СЕРВЕР"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _startServer,
            )
          else ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text("СВЯЗАТЬ С БРАУЗЕРОМ"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _scanQr,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              icon: const Icon(Icons.stop, size: 18),
              label: const Text("Остановить сервер"),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _stopServer,
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
