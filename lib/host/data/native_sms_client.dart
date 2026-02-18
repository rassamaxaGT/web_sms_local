import 'dart:async';
import 'package:flutter/services.dart';
import '../../shared/shared_models.dart';

class NativeSmsClient {
  static const _methodChannel = MethodChannel('com.example.sms_host/methods');
  static const _eventChannel = EventChannel('com.example.sms_host/events');

  Stream<SmsMessageDto> get onSmsReceived {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      // FIX: Безопасное приведение типов
      if (event == null) throw Exception("Empty event");
      final map = Map<String, dynamic>.from(event as Map);
      return SmsMessageDto(
        address: map['address']?.toString() ?? 'Unknown',
        body: map['body']?.toString() ?? '',
        // FIX: Проверка на int, так как иногда может приходить Long или Double в зависимости от платформы
        date: (map['date'] is int)
            ? map['date']
            : DateTime.now().millisecondsSinceEpoch,
        isSent: false,
        subId: map['subId'] is int ? map['subId'] : null,
      );
    });
  }

  Future<List<SimCardDto>> getSimCards() async {
    try {
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getSimCards',
      );
      if (result == null) return [];

      return result.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        return SimCardDto(
          subscriptionId: map['subscriptionId'] as int? ?? -1,
          slotIndex: map['slotIndex'] as int? ?? -1,
          carrierName: map['carrierName']?.toString() ?? "Unknown",
        );
      }).toList();
    } catch (e) {
      print("Error fetching SIMs: $e");
      return [];
    }
  }

  Future<void> sendSms(String address, String body, int subId) async {
    try {
      await _methodChannel.invokeMethod('sendSms', {
        'address': address,
        'body': body,
        'subId': subId, // Убедитесь, что subId передается как int
      });
    } catch (e) {
      print("Native send error: $e");
      rethrow;
    }
  }

  Future<List<SmsMessageDto>> getFullHistory() async {
    try {
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getAllMessages',
      );
      if (result == null) return [];

      return result.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        return SmsMessageDto(
          id: map['id'] as int?,
          threadId: map['threadId'] as int?,
          address: map['address']?.toString() ?? 'Unknown',
          body: map['body']?.toString() ?? '',
          // FIX: Защита от null даты
          date: (map['date'] is int)
              ? map['date']
              : DateTime.now().millisecondsSinceEpoch,
          isSent:
              map['isSent'] == true ||
              map['type'] ==
                  2, // Иногда Android использует type=2 для отправленных
          subId: map['subId'] as int?,
        );
      }).toList();
    } catch (e) {
      print("History fetch error: $e");
      return [];
    }
  }

  // === МЕТОДЫ УДАЛЕНИЯ ===
  Future<void> deleteMessage(int id) async {
    await _methodChannel.invokeMethod('deleteSms', {'id': id});
  }

  Future<void> deleteThread(int threadId) async {
    await _methodChannel.invokeMethod('deleteThread', {'threadId': threadId});
  }
}
