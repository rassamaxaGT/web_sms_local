import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'providers.dart'; // To access globalContainer and selectedChatIdProvider

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const WindowsInitializationSettings initializationSettingsWindows =
          WindowsInitializationSettings(
        appName: 'SMS Web Client',
        appUserModelId: 'com.example.web_sms_local',
        guid: '3a8e32c0-7f2a-11ed-a1eb-0242ac120002',
      );

      // InitializationSettings for standard platform initialization
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        windows: initializationSettingsWindows,
      );

      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _handleNotificationClick(payload);
          }
        },
      );
      _initialized = true;
    } catch (e) {
      debugPrint("Failed to initialize NotificationService: $e");
    }
  }

  Future<void> show(String title, String body, {String? payload}) async {
    await init();
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'crm_callbacks',
        'CRM Callbacks',
        channelDescription: 'Notifications for scheduled CRM calls',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      await _plugin.show(
        DateTime.now().millisecond, // Unique ID
        title,
        body,
        platformDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint("Failed to show notification: $e");
    }
  }

  void _handleNotificationClick(String phone) {
    if (globalContainer != null) {
      try {
        globalContainer!.read(selectedChatIdProvider.notifier).select(phone);
      } catch (e) {
        debugPrint("Error handling notification click: $e");
      }
    }
  }
}
