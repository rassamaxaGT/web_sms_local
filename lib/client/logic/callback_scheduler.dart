import 'dart:async';
import 'package:flutter/foundation.dart';
import 'providers.dart';
import 'notification_service.dart';
import '../../shared/shared_models.dart';

class CallbackScheduler {
  static final CallbackScheduler instance = CallbackScheduler._();
  CallbackScheduler._();

  Timer? _timer;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkCallbacks();
    });
    // Run initial check immediately
    _checkCallbacks();
  }

  void stop() {
    _timer?.cancel();
    _running = false;
  }

  void _checkCallbacks() {
    if (globalContainer == null) return;

    try {
      final contacts = globalContainer!.read(contactsProvider);
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final contact in contacts) {
        final callbackTime = contact.callbackTimeMs;
        if (callbackTime != null && now >= callbackTime) {
          _fireNotification(contact);
        }
      }
    } catch (e) {
      debugPrint("Error checking callbacks: $e");
    }
  }

  Future<void> _fireNotification(ContactDto contact) async {
    final callbackTime = contact.callbackTimeMs;
    if (callbackTime == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final isMissed = now - callbackTime > 60000; // Missed by more than 1 minute

    final title = isMissed 
        ? "Пропущенный звонок: ${contact.name.isNotEmpty ? contact.name : contact.phone}"
        : "Запланированный звонок: ${contact.name.isNotEmpty ? contact.name : contact.phone}";
    
    final body = isMissed
        ? "Звонок был запланирован на ${contact.callbackTime?.toLocal().toString().substring(11, 16)} (${contact.callbackTime?.toLocal().toString().substring(0, 10)})"
        : "Время связаться с клиентом. Номер: ${contact.phone}";

    // Log missed callback and clear it from the schedule to avoid double triggers
    if (globalContainer != null) {
      await globalContainer!.read(contactsProvider.notifier).logMissedCallback(contact);
    }

    // Show the notification toast on PC
    await NotificationService.instance.show(title, body, payload: contact.phone);
  }
}
