import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  // Контроллер для управления камерой
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null) {
        debugPrint('QR Code detected: $rawValue'); // Видно в консоли

        try {
          final data = jsonDecode(rawValue);

          // Проверяем наличие наших ключей из Веб-приложения
          if (data is Map &&
              data.containsKey('pass') &&
              data.containsKey('id')) {
            _isScanned = true;

            // Останавливаем камеру перед выходом
            _controller.stop();

            debugPrint('Valid QR Data found: $data');

            // Возвращаем результат обратно в main.dart
            Navigator.pop(context, {
              'pass': data['pass'].toString(),
              'id': data['id'].toString(),
            });
            return;
          }
        } catch (e) {
          // Если это не JSON или в нем нет нужных полей, просто игнорируем
          debugPrint('Scanned QR is not a valid JSON: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Web QR"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Сам сканер
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Рамка визуального наведения
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Подсказка снизу
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                "Point your camera at the PC screen",
                style: TextStyle(
                  color: Colors.white,
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
