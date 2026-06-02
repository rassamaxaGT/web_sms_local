import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../shared/theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
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
        debugPrint('QR Code detected: $rawValue');

        try {
          final data = jsonDecode(rawValue);

          if (data is Map &&
              data.containsKey('pass') &&
              data.containsKey('id')) {
            _isScanned = true;
            _controller.stop();

            debugPrint('Valid QR Data found: $data');

            Navigator.pop(context, {
              'pass': data['pass'].toString(),
              'id': data['id'].toString(),
            });
            return;
          }
        } catch (e) {
          debugPrint('Scanned QR is not a valid JSON: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "СОПРЯЖЕНИЕ",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontFamily: 'Outfit',
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            SfxService.playSent();
            Navigator.pop(context);
          },
        ),
      ),
      body: Stack(
        children: [
          // Camera scanner
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // High-Tech Dark HUD overlay masks
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),

          // Custom high-tech glowing transparent frame cut out
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              child: CustomPaint(
                painter: ScanCornersPainter(),
              ),
            ),
          ),

          // Glowing laser line scanner animation
          const Center(child: LaserScannerAnimation()),

          // Monospace HUD Instructions
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: AppColors.success, size: 16),
                      SizedBox(width: 8),
                      Text(
                        "НАВЕДИТЕ НА QR-КОД В БРАУЗЕРЕ",
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter to draw beautiful glowing brackets around scanning frame
class ScanCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = AppColors.success.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round;

    const cornerLength = 32.0;

    // Draw helper path for glow then solid color
    for (var currentPaint in [glowPaint, paint]) {
      // Top Left Corner
      canvas.drawLine(const Offset(0, 0), const Offset(cornerLength, 0), currentPaint);
      canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLength), currentPaint);

      // Top Right Corner
      canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), currentPaint);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), currentPaint);

      // Bottom Left Corner
      canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), currentPaint);
      canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), currentPaint);

      // Bottom Right Corner
      canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), currentPaint);
      canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Simple animated laser bar scan effect
class LaserScannerAnimation extends StatefulWidget {
  const LaserScannerAnimation({super.key});

  @override
  State<LaserScannerAnimation> createState() => _LaserScannerAnimationState();
}

class _LaserScannerAnimationState extends State<LaserScannerAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -110 + _controller.value * 220),
          child: Container(
            width: 220,
            height: 2,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.8),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
              color: AppColors.success,
            ),
          ),
        );
      },
    );
  }
}
