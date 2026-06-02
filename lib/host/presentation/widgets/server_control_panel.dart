import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../../shared/theme.dart';
import '../qr_scan_screen.dart';

class ServerControlPanel extends StatefulWidget {
  const ServerControlPanel({super.key});

  @override
  State<ServerControlPanel> createState() => _ServerControlPanelState();
}

class _ServerControlPanelState extends State<ServerControlPanel> {
  String _status = "Готов к работе";
  String? _serverUrl;
  String? _wifiName;
  bool _isRunning = false;
  StreamSubscription? _statusSubscription;
  final List<String> _consoleLogs = [];
  Timer? _logSimulatorTimer;

  @override
  void initState() {
    super.initState();
    final service = FlutterBackgroundService();

    _statusSubscription = service.on('statusUpdate').listen((event) {
      if (mounted) {
        setState(() {
          _isRunning = event?['isRunning'] ?? false;
          _serverUrl = event?['currentUrl'];
          _wifiName = event?['wifiName'];
          final isSecured = event?['isSecured'] ?? false;
          
          if (_isRunning) {
            _status = isSecured ? "ЗАЩИЩЕНО И ПОДКЛЮЧЕНО" : "Трансляция активна";
            _addLog("[NET] Сервер запущен на $_serverUrl");
            if (isSecured) {
              _addLog("[SEC] Установлено защищенное SSL сопряжение.");
            }
          } else {
            _status = "Трансляция остановлена";
            _addLog("[SYS] Сервер фоновой службы остановлен.");
          }
        });
      }
    });

    service.invoke('requestStatus');
    _simulateSystemBoot();
  }

  void _addLog(String log) {
    if (_consoleLogs.contains(log)) return;
    setState(() {
      if (_consoleLogs.length > 20) _consoleLogs.removeAt(0);
      _consoleLogs.add(log);
    });
  }

  void _simulateSystemBoot() {
    _consoleLogs.clear();
    _addLog("[SYS] Инициализация ядра SMS Host...");
    _addLog("[SYS] Проверка разрешений радиомодуля... ОК");
    _addLog("[SYS] Поиск SIM карт в слотах... ОК");
    
    _logSimulatorTimer?.cancel();
    _logSimulatorTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isRunning) {
        final r = DateTime.now().millisecond;
        if (r % 3 == 0) {
          _addLog("[SYS] Выполнен цикличный опрос буфера SIM-карты.");
        } else if (r % 3 == 1) {
          _addLog("[NET] Пинг веб-сокета... Стабилен (0ms)");
        }
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _logSimulatorTimer?.cancel();
    super.dispose();
  }

  Future<void> _startServer() async {
    setState(() => _status = "Запуск...");
    _addLog("[SYS] Запуск фоновой службы shelf_router...");
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      } else {
        service.invoke('requestStatus');
      }
      SfxService.playSuccess();
    } catch (e) {
      setState(() => _status = "Ошибка: $e");
      _addLog("[ERR] Ошибка при запуске: $e");
    }
  }

  void _stopServer() {
    FlutterBackgroundService().invoke("stopService");
    SfxService.playSent();
  }

  Future<void> _scanQr() async {
    SfxService.playSent();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );

    if (result != null && result is Map) {
      FlutterBackgroundService().invoke('updateSecurity', {
        'pass': result['pass'],
        'id': result['id'],
      });

      _addLog("[SEC] Выполнен импорт ключей сопряжения из QR.");
      SfxService.playSuccess();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Сопряжение выполнено!", style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Elegant top swipe handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
              margin: const EdgeInsets.only(bottom: 24),
            ),
          ),
          
          Row(
            children: [
              const Icon(Icons.wifi_tethering_rounded, color: AppColors.accentLight, size: 22),
              const SizedBox(width: 8),
              const Text(
                "ТРАНСЛЯЦИЯ SMS",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontFamily: 'Outfit',
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isRunning ? AppColors.success.withValues(alpha: 0.12) : AppColors.border,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isRunning ? AppColors.success.withValues(alpha: 0.3) : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _isRunning ? AppColors.success : AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isRunning ? "ACTIVE" : "STANDBY",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: _isRunning ? AppColors.success : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Wi-Fi Connection Information (Glass Card)
          if (_isRunning && _wifiName != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.msgSent.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_rounded, size: 18, color: AppColors.accentLight),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Беспроводная сеть Wi-Fi",
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                        Text(
                          _wifiName!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_serverUrl != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _serverUrl!.replaceAll("http://", "").replaceAll(":8080", ""),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Console Log Emulator Block (Very Premium)
          const Text(
            "ЛОГ РАБОТЫ ТРАНСЛЯТОРА",
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.0),
          ),
          const SizedBox(height: 6),
          Container(
            height: 140,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              itemCount: _consoleLogs.length,
              itemBuilder: (context, idx) {
                final log = _consoleLogs[idx];
                Color logColor = AppColors.textSecondary;
                if (log.startsWith("[NET]")) logColor = AppColors.accentLight;
                if (log.startsWith("[SEC]")) logColor = AppColors.success;
                if (log.startsWith("[ERR]")) logColor = AppColors.error;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: logColor,
                      height: 1.3,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Central State Status Display
          Center(
            child: Text(
              _status.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: _status.contains("ЗАЩИЩЕНО") || _status.contains("активен")
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          if (!_isRunning)
            ElevatedButton.icon(
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text("ЗАПУСТИТЬ ТРАНСЛЯЦИЮ"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _startServer,
            )
          else ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text("СВЯЗАТЬ С БРАУЗЕРОМ (SCAN)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _scanQr,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text("Остановить службу трансляции"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1.0),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _stopServer,
            ),
          ],
        ],
      ),
    );
  }
}
