import 'dart:async';
import 'package:flutter/services.dart';
import '../../shared/shared_models.dart';

class NativeSmsClient {
  static const _methodChannel = MethodChannel('com.example.sms_host/methods');
  static const _eventChannel = EventChannel('com.example.sms_host/events');
  
  Stream<SmsMessageDto> get onSmsReceived {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      final map = Map<String, dynamic>.from(event);
      return SmsMessageDto(
        address: map['address'] ?? 'Unknown',
        body: map['body'] ?? '',
        date: map['date'] is int ? map['date'] : DateTime.now().millisecondsSinceEpoch,
        isSent: false,
        subId: map['subId'],
      );
    });
  }

  Future<List<SimCardDto>> getSimCards() async {
    try {
      final List<dynamic> result = await _methodChannel.invokeMethod('getSimCards');
      return result.map((data) {
        final map = Map<String, dynamic>.from(data);
        return SimCardDto(
          subscriptionId: map['subscriptionId'],
          slotIndex: map['slotIndex'],
          carrierName: map['carrierName'] ?? "Unknown",
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> sendSms(String address, String body, int subId) async {
    await _methodChannel.invokeMethod('sendSms', {
      'address': address,
      'body': body,
      'subId': subId,
    });
  }
  
  Future<List<SmsMessageDto>> getFullHistory() async {
    try {
      final List<dynamic> result = await _methodChannel.invokeMethod('getAllMessages');
      return result.map((data) {
        final map = Map<String, dynamic>.from(data);
        return SmsMessageDto(
          id: map['id'],             // ID
          threadId: map['threadId'], // ID диалога
          address: map['address'] ?? 'Unknown',
          body: map['body'] ?? '',
          date: map['date'] ?? DateTime.now().millisecondsSinceEpoch,
          isSent: map['isSent'] == true,
          subId: map['subId'],
        );
      }).toList();
    } catch (e) {
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