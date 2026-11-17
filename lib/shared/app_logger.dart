import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized logger and crash handler for SMS Host
class AppLogger {
  static const _diagChannel = MethodChannel('com.example.sms_host/diagnostics');
  static final List<String> _logs = [];
  static final StreamController<String> _logStream = StreamController<String>.broadcast();
  static File? _logFile;
  static bool _initialized = false;

  static Stream<String> get onLog => _logStream.stream;
  static List<String> get logs => List.unmodifiable(_logs);

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/app_startup.log');
      
      // If log file exists and is > 1MB, clear it
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > 1024 * 1024) {
          await _logFile!.writeAsString('');
        }
      }
      log("Logger initialized. Log file path: ${_logFile!.path}", tag: "SYS");

      // Check for previous native crash logs
      final nativeCrash = await getNativeLogs();
      if (nativeCrash.isNotEmpty && !nativeCrash.startsWith("No native")) {
        log("⚠️ Previous native crash logs detected:\n$nativeCrash", tag: "NATIVE_CRASH_DETECTED");
      }
    } catch (e) {
      debugPrint("[LOGGER_INIT_ERROR] $e");
    }
  }

  static void log(String message, {String tag = "APP", Object? error, StackTrace? stackTrace}) {
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}";
    final entry = "[$timeStr][$tag] $message${error != null ? '\nError: $error' : ''}${stackTrace != null ? '\nStack: $stackTrace' : ''}";
    
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    
    debugPrint(entry);
    _logStream.add(entry);

    // Asynchronously write to file
    _writeToFile(entry);
  }

  static void error(String message, {String tag = "ERROR", Object? error, StackTrace? stackTrace}) {
    log("❌ $message", tag: tag, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {String tag = "INFO"}) {
    log("ℹ️ $message", tag: tag);
  }

  static void success(String message, {String tag = "OK"}) {
    log("✅ $message", tag: tag);
  }

  static void warning(String message, {String tag = "WARN"}) {
    log("⚠️ $message", tag: tag);
  }

  static Future<void> _writeToFile(String entry) async {
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString("$entry\n", mode: FileMode.append, flush: true);
      }
    } catch (_) {}
  }

  static Future<String> getFullLogText() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (_) {}
    return _logs.join('\n');
  }

  static Future<String> getNativeLogs() async {
    if (kIsWeb || !Platform.isAndroid) return "Not supported on this platform";
    try {
      final String? nativeLogs = await _diagChannel.invokeMethod<String>('getNativeLogs');
      return nativeLogs ?? "No native logs recorded.";
    } catch (e) {
      return "Failed to fetch native logs: $e";
    }
  }

  static Future<String?> exportLogsToDownloads() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final fullDartLogs = await getFullLogText();
      final nativeLogs = await getNativeLogs();
      final combined = "=== SMS HOST FULL DIAGNOSTICS EXPORT ===\n"
          "Generated at: ${DateTime.now().toIso8601String()}\n\n"
          "--- DART & FLUTTER LOGS ---\n$fullDartLogs\n\n"
          "--- NATIVE ANDROID LOGS ---\n$nativeLogs\n";

      final String? path = await _diagChannel.invokeMethod<String>(
        'exportLogsToDownloads',
        {'content': combined},
      );
      return path;
    } catch (e) {
      error("Export to downloads failed", tag: "EXPORT", error: e);
      return null;
    }
  }
}

/// Full Diagnostics Viewer Screen (usable from Startup Error or Diagnostics Button)
class StartupErrorScreen extends StatefulWidget {
  final Object? error;
  final StackTrace? stackTrace;
  final VoidCallback? onRetry;

  const StartupErrorScreen({
    super.key,
    this.error,
    this.stackTrace,
    this.onRetry,
  });

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _nativeLogText = "Загрузка нативных логов...";
  Map<String, String> _systemInfo = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllDiagnostics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllDiagnostics() async {
    setState(() => _isLoading = true);
    final nativeLogs = await AppLogger.getNativeLogs();
    
    final smsStatus = await Permission.sms.status;
    final phoneStatus = await Permission.phone.status;
    final notifStatus = await Permission.notification.status;
    final contactStatus = await Permission.contacts.status;

    if (mounted) {
      setState(() {
        _nativeLogText = nativeLogs;
        _systemInfo = {
          "Платформа": Platform.operatingSystem,
          "Версия ОС": Platform.operatingSystemVersion,
          "Разрешение SMS": smsStatus.name,
          "Разрешение Phone": phoneStatus.name,
          "Разрешение Notifications": notifStatus.name,
          "Разрешение Contacts": contactStatus.name,
          "Локальное время": DateTime.now().toLocal().toString(),
        };
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dartLogs = AppLogger.logs.join('\n');
    final isCrash = widget.error != null;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Icon(
              isCrash ? Icons.error_outline_rounded : Icons.receipt_long_rounded,
              color: isCrash ? Colors.redAccent : Colors.cyanAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              isCrash ? "ОШИБКА ЗАПУСКА" : "ЖУРНАЛ ДИАГНОСТИКИ",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isCrash ? Colors.redAccent : Colors.white,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: "Dart Логи"),
            Tab(text: "Native Android"),
            Tab(text: "Система"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : Column(
              children: [
                if (widget.error != null)
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: SelectableText(
                      "Исключение: ${widget.error}\n\nСтек:\n${widget.stackTrace ?? 'нет стека'}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // 1. Dart Logs
                      _buildLogViewer(dartLogs.isEmpty ? "Логи Dart пусты" : dartLogs),

                      // 2. Native Android Logs
                      _buildLogViewer(_nativeLogText),

                      // 3. System Info
                      _buildSystemInfo(),
                    ],
                  ),
                ),
                _buildActionButtons(context),
              ],
            ),
    );
  }

  Widget _buildLogViewer(String content) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          content,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontFamily: 'monospace',
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildSystemInfo() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _systemInfo.entries.map((e) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                e.value,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final allLogs = "=== DART LOGS ===\n${AppLogger.logs.join('\n')}\n\n=== NATIVE LOGS ===\n$_nativeLogText";
                await Clipboard.setData(ClipboardData(text: allLogs));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Логи скопированы в буфер обмена"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text("Скопировать", style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final path = await AppLogger.exportLogsToDownloads();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(path != null ? "Сохранено в Downloads: $path" : "Ошибка сохранения"),
                      backgroundColor: path != null ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text("В Загрузки", style: TextStyle(fontSize: 12)),
            ),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(width: 8),
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}
