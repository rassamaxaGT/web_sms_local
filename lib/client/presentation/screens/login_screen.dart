import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import '../../logic/providers.dart';
import '../../logic/network_scanner.dart';
import '../../../shared/theme.dart';
import 'home_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  String _status = "Инициализация системы...";
  String? _foundHost;
  late final String _password;
  late final String _sessionId;
  bool _isScanning = true;
  Timer? _pollingTimer;

  // Animation controller for the background mesh bubbles
  late final AnimationController _bgAnimationController;

  @override
  void initState() {
    super.initState();
    _password = const Uuid().v4().substring(0, 8);
    _sessionId = const Uuid().v4().substring(0, 6);
    
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();

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
    _bgAnimationController.dispose();
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
      SfxService.playSuccess();
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
        title: const Text(
          "Ввести IP вручную",
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Укажите IP-адрес хост-устройства из приложения на телефоне.",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: "192.168.x.x",
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.lan, color: AppColors.accent),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent, width: 2),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена", style: TextStyle(color: AppColors.textSecondary)),
          ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
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
      body: Stack(
        children: [
          // Moving Mesh Gradient Background
          AnimatedBuilder(
            animation: _bgAnimationController,
            builder: (context, child) {
              final angle = _bgAnimationController.value * 2 * math.pi;
              return Stack(
                children: [
                  Container(color: AppColors.background),
                  // Left top steel-violet bubble
                  Positioned(
                    top: -150 + math.sin(angle) * 80,
                    left: -150 + math.cos(angle) * 80,
                    child: Container(
                      width: 500,
                      height: 500,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x1F6366F1), // 12% opacity royal blue-violet
                            Color(0x006366F1),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Right bottom charcoal violet bubble
                  Positioned(
                    bottom: -200 + math.cos(angle) * 90,
                    right: -100 + math.sin(angle) * 90,
                    child: Container(
                      width: 600,
                      height: 600,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x14818CF8), // 8% opacity slate lavender
                            Color(0x00818CF8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Center glowing blue-violet accent
                  Positioned(
                    top: MediaQuery.of(context).size.height / 2 - 250 + math.sin(angle + math.pi) * 60,
                    left: MediaQuery.of(context).size.width / 2 - 250 + math.cos(angle + math.pi) * 60,
                    child: Container(
                      width: 500,
                      height: 500,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x0F4F46E5), // 6% opacity deep violet
                            Color(0x004F46E5),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          
          // Outer overlay dot pattern
          Positioned.fill(
            child: Opacity(
              opacity: 0.015,
              child: Image.asset(
                'assets/images/dot_pattern.png', // Fallback pattern if none, we will paint dots programmatically if needed
                errorBuilder: (context, error, stackTrace) {
                  return const CustomPaint(painter: DotPatternPainter());
                },
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Central Login Panel
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Hero(
                tag: 'login_panel',
                child: GlassCard(
                  width: 440,
                  borderRadius: 24,
                  blur: 20,
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // High-tech logo badge
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.msgSent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          size: 40,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "SMS CLIENT",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          fontFamily: 'Outfit',
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "СВЯЗЬ ЗАЩИЩЕНА",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: AppColors.accent.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Animated scanning / state container
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildStateContent(qrData),
                      ),
                      
                      const SizedBox(height: 24),
                      const Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 16),
                      
                      // Bottom hint
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.security, size: 14, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Text(
                            "Локальное сквозное шифрование",
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateContent(String qrData) {
    if (_isScanning) {
      return Column(
        key: const ValueKey('scanning'),
        children: [
          const SizedBox(
            height: 60,
            width: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      );
    } else if (_foundHost != null) {
      return Column(
        key: const ValueKey('qr_ready'),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              size: 190.0,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: Color(0xFF0F1014),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Color(0xFF0F1014),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.msgSent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _foundHost!.replaceAll("http://", "").replaceAll(":8080", ""),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        key: const ValueKey('error'),
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text("Повторить поиск"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showManualIpDialog,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text("Ввести IP вручную"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
  }
}