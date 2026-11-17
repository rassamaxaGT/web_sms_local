import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart';
import 'host/service/background_service_logic.dart';
import 'host/presentation/screens/inbox_screen.dart';
import 'shared/theme.dart';
import 'shared/app_logger.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch all Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger.error(
        "Flutter Framework Error: ${details.exceptionAsString()}",
        tag: "FLUTTER_ERROR",
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };

    // Catch platform errors
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.error(
        "Platform Dispatcher Error: $error",
        tag: "PLATFORM_ERROR",
        error: error,
        stackTrace: stack,
      );
      return true;
    };

    // Initialize local file logger
    await AppLogger.init();
    AppLogger.info("Starting SMS Host Application...", tag: "BOOT");

    // 1. Orientations
    try {
      AppLogger.info("Setting device orientations...", tag: "BOOT");
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      AppLogger.success("Orientations set successfully.", tag: "BOOT");
    } catch (e, stack) {
      AppLogger.error("Failed to set orientations", tag: "BOOT", error: e, stackTrace: stack);
    }

    // 2. Background Service
    try {
      AppLogger.info("Initializing Background Service...", tag: "BOOT");
      await initializeBackgroundService();
      AppLogger.success("Background service configured.", tag: "BOOT");
    } catch (e, stack) {
      AppLogger.error("Failed to initialize background service", tag: "BOOT", error: e, stackTrace: stack);
    }

    // 3. Sound Effects
    try {
      AppLogger.info("Initializing SFX Service...", tag: "BOOT");
      SfxService.init();
      AppLogger.success("SFX service initialized.", tag: "BOOT");
    } catch (e, stack) {
      AppLogger.error("Failed to initialize SFX", tag: "BOOT", error: e, stackTrace: stack);
    }

    AppLogger.info("Launching main UI...", tag: "BOOT");

    // Global widget error builder
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: StartupErrorScreen(
          error: details.exception,
          stackTrace: details.stack,
        ),
      );
    };

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SMS Host',
      themeMode: ThemeMode.dark,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const InboxScreen(),
    ));
  }, (Object error, StackTrace stackTrace) {
    AppLogger.error(
      "Uncaught Zoned Error: $error",
      tag: "FATAL_ZONE",
      error: error,
      stackTrace: stackTrace,
    );

    // If runApp hasn't completed or crashed completely, show fallback error UI
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: StartupErrorScreen(
        error: error,
        stackTrace: stackTrace,
        onRetry: () => main(),
      ),
    ));
  });
}