import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'storage_helper.dart' as storage;

/// Strict Charcoal & Graphite Color Palette
class AppColors {
  static const Color background = Color(0xFF07080B); // Obsidian Dark (higher glass contrast)
  static const Color cardBg = Color(0x4D0E0F12); // Translucent Obsidian Card (30% opacity)
  static const Color cardBgLight = Color(0xB3FFFFFF); // Translucent White Card (70% opacity)
  static const Color cardBgSolid = Color(0xFF16181D); // Solid Obsidian Card (perfect contrast for dialogs & popups)
  
  static const Color accent = Color(0xFF6366F1); // Elegant Slate Blue-Violet
  static const Color accentLight = Color(0xFF818CF8); // Soft Lavender-Slate
  
  static const Color textPrimary = Color(0xFFF8FAFC); // Crisp slate 50
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900
  static const Color textSecondaryLight = Color(0xFF475569); // Slate 600

  static const Color border = Color(0x1BFFFFFF); // Shiny white border 10.5% (sharp glass refraction)
  static const Color borderLight = Color(0x1A000000); // Black border 10%
  
  static const Color success = Color(0xFF818CF8); // Elegant lavender-slate for success/online state!
  static const Color warning = Color(0xFF4F46E5); // Subtle royal blue-violet warning!
  static const Color error = Color(0xFFF87171); // Soft Rose 400
  
  // Translucent elegant message bubbles
  static const Color msgSent = Color(0x596366F1); // 35% opacity blue-violet bubble for sent
  static const Color msgReceived = Color(0x591E2026); // 35% opacity dark charcoal for received
  static const Color msgSentLight = Color(0xFFE2E8F0); 
  static const Color msgReceivedLight = Color(0xFFF1F5F9);
}

/// Centralized Theme configuration
class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.accent,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.cardBg,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBgSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 24,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textSecondary),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.accentLight,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      cardColor: AppColors.cardBgLight,
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 16,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimaryLight),
        bodyMedium: TextStyle(color: AppColors.textSecondaryLight),
      ),
      useMaterial3: true,
    );
  }
}

/// Custom Glassmorphic Card utilizing BackdropFilter
class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final Clip clipBehavior;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 18.0,
    this.borderRadius = 16.0,
    this.color,
    this.border,
    this.boxShadow,
    this.padding,
    this.width,
    this.height,
    this.clipBehavior = Clip.antiAlias,
  });

  // Performance override: can be set to false globally if lagging
  static bool enableBlur = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBgColor = color ?? 
        (isDark 
            ? AppColors.cardBg 
            : AppColors.cardBgLight);
            
    final defaultBorder = border ?? Border.all(
      color: isDark ? AppColors.border : AppColors.borderLight,
      width: 1.0,
    );

    final cardWidget = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: defaultBgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: defaultBorder,
        boxShadow: boxShadow ?? [
          BoxShadow(
            color: isDark ? Colors.black38 : Colors.black12,
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );

    if (!enableBlur || blur <= 0.0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: clipBehavior,
        child: cardWidget,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: cardWidget,
      ),
    );
  }
}

/// Sound Effects (SFX) Service
class SfxService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _soundEnabled = false;

  static void init() {
    if (kIsWeb) {
      _soundEnabled = storage.getSoundEnabled();
    }
  }

  static bool get isSoundEnabled => _soundEnabled;

  static void toggleSound(bool enabled) {
    _soundEnabled = enabled;
    if (kIsWeb) {
      storage.setSoundEnabled(enabled);
    }
  }

  static Future<void> playSent() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/notification.mp3'));
    } catch (_) {
      // Ignore audio errors gracefully (especially browser auto-play blocks)
    }
  }

  static Future<void> playReceived() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/notification.mp3'));
    } catch (_) {}
  }

  static Future<void> playSuccess() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/notification.mp3'));
    } catch (_) {}
  }
}

/// Custom painter to draw high-tech dot pattern when background assets are not loaded
class DotPatternPainter extends CustomPainter {
  const DotPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

