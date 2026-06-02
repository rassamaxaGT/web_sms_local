import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_host/host/server/server_manager.dart';

Future<void> initializeBackgroundService() async {
  try {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sms_server_channel',
      'SMS Server Service',
      importance: Importance.low,
    );

    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

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
  } catch (e, stack) {
    debugPrint("ERROR INITIALIZING BACKGROUND SERVICE: $e");
    debugPrint(stack.toString());
  }
}


@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Гарантируем регистрацию плагинов (включая наш локальный плагин) во внешнем изоляте
  DartPluginRegistrant.ensureInitialized();

  final ServerManager serverManager = ServerManager();

  void sendStatus() {
    service.invoke('statusUpdate', {
      'isRunning': serverManager.isRunning,
      'currentUrl': serverManager.currentUrl,
      'wifiName': serverManager.wifiName,
      'isSecured': serverManager.isSecured,
    });
  }

  // 1. Автоматический запуск сервера при старте службы
  try {
    final url = await serverManager.start();
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Server Active',
        content: 'Server is running at: $url',
      );
    }
    sendStatus();
  } catch (e) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SMS Server Error',
        content: e.toString(),
      );
    }
    sendStatus();
  }

  // 2. Обработчик запроса статуса из UI
  service.on('requestStatus').listen((event) {
    sendStatus();
  });

  // 3. Обработчик обновления пароля и сессии (после сканирования QR)
  service.on('updateSecurity').listen((event) {
    if (event != null && event.containsKey('pass') && event.containsKey('id')) {
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
  });

  // 4. Обработчик остановки службы
  service.on('stopService').listen((event) async {
    serverManager.stop();
    sendStatus();
    await service.stopSelf();
  });
}
