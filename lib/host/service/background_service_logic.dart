import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_host/host/server/server_manager.dart';
import 'package:android_host/shared/app_logger.dart';

Future<void> initializeBackgroundService() async {
  try {
    AppLogger.info("Creating FlutterBackgroundService instance...", tag: "BKG_SVC");
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sms_server_channel',
      'SMS Server Service',
      description: 'Foreground service for SMS Gateway and Web Server',
      importance: Importance.low,
    );

    AppLogger.info("Initializing FlutterLocalNotificationsPlugin...", tag: "BKG_SVC");
    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await notificationsPlugin.initialize(initSettings);
    AppLogger.success("NotificationsPlugin initialized.", tag: "BKG_SVC");

    AppLogger.info("Creating notification channel sms_server_channel...", tag: "BKG_SVC");
    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    AppLogger.success("Notification channel created.", tag: "BKG_SVC");

    AppLogger.info("Configuring service parameters...", tag: "BKG_SVC");
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'sms_server_channel',
        initialNotificationTitle: 'SMS Server Running',
        initialNotificationContent: 'Ready to sync...',
      ),
      iosConfiguration: IosConfiguration(),
    );
    AppLogger.success("Background service configure finished.", tag: "BKG_SVC");
  } catch (e, stack) {
    AppLogger.error("Failed to initialize background service", tag: "BKG_SVC", error: e, stackTrace: stack);
  }
}


@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Guarantee plugin registration in background isolate
  DartPluginRegistrant.ensureInitialized();
  debugPrint("[ISOLATE] Background service isolate started.");

  final ServerManager serverManager = ServerManager();

  void sendStatus() {
    service.invoke('statusUpdate', {
      'isRunning': serverManager.isRunning,
      'currentUrl': serverManager.currentUrl,
      'wifiName': serverManager.wifiName,
      'isSecured': serverManager.isSecured,
    });
  }

  final subscriptions = <StreamSubscription>[];

  // Register handlers BEFORE starting server so UI events during startup are not lost
  subscriptions.add(
    service.on('requestStatus').listen((event) {
      sendStatus();
    }),
  );

  subscriptions.add(
    service.on('updateSecurity').listen((event) {
      if (event != null && event.containsKey('pass') && event.containsKey('id')) {
        debugPrint("[ISOLATE] Updating security password/sessionId");
        serverManager.updatePassword(
          event['pass'].toString(),
          event['id'].toString(),
        );
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'SMS Server Active (SECURED)',
            content: 'Server is running at: ${serverManager.currentUrl}',
          );
        }
        sendStatus();
      }
    }),
  );

  subscriptions.add(
    service.on('stopService').listen((event) async {
      debugPrint("[ISOLATE] Stopping service...");
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      subscriptions.clear();
      await serverManager.stop();
      sendStatus();
      await service.stopSelf();
    }),
  );

  // 1. Start server automatically on background service start
  try {
    debugPrint("[ISOLATE] Starting ServerManager...");
    final url = await serverManager.start();
    debugPrint("[ISOLATE] ServerManager started at: $url");
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Server Active',
        content: 'Server is running at: $url',
      );
    }
    sendStatus();
  } catch (e, stack) {
    debugPrint("[ISOLATE_ERROR] Server start failed: $e\n$stack");
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Server Error',
        content: e.toString(),
      );
    }
    sendStatus();
  }
}
