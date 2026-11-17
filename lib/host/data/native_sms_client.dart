import 'dart:async';
import 'package:flutter/services.dart';
import '../../shared/shared_models.dart';
import '../../shared/app_logger.dart';

class NativeSmsClient {
  static const _methodChannel = MethodChannel('com.example.sms_host/methods');
  static const _eventChannel = EventChannel('com.example.sms_host/events');
  static const _callEventChannel = EventChannel('com.example.sms_host/call_events');
  static const _deviceEventChannel = EventChannel('com.example.sms_host/device_events');

  Future<List<CallLogEntryDto>> getCallLogs({int limit = 100, int offset = 0}) async {
    try {
      AppLogger.info("Invoking getCallLogs (limit=$limit, offset=$offset)...", tag: "CALL_CHANNEL");
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getCallLogs',
        {'limit': limit, 'offset': offset},
      );
      if (result == null) return [];

      final logs = result.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        final rawType = map['type']?.toString().toUpperCase() ?? 'UNKNOWN';
        final duration = map['durationSeconds'] as int? ?? 0;

        String direction = 'incoming';
        String status = 'успех';

        if (rawType == 'OUTGOING') {
          direction = 'outgoing';
          status = duration > 0 ? 'успех' : 'ндз';
        } else if (rawType == 'MISSED') {
          direction = 'incoming';
          status = 'пропущен';
        } else if (rawType == 'REJECTED') {
          direction = 'incoming';
          status = 'сброшен';
        } else if (rawType == 'BLOCKED') {
          direction = 'incoming';
          status = 'заблокирован';
        } else {
          direction = 'incoming';
          status = duration > 0 ? 'принят' : 'без ответа';
        }

        return CallLogEntryDto(
          id: map['id']?.toString() ?? '',
          number: map['number']?.toString() ?? '',
          name: (map['name'] != null && map['name'].toString().isNotEmpty)
              ? map['name'].toString()
              : null,
          date: map['date'] as int? ?? 0,
          durationSeconds: duration,
          direction: direction,
          status: status,
        );
      }).toList();
      AppLogger.success("getCallLogs returned ${logs.length} entries", tag: "CALL_CHANNEL");
      return logs;
    } catch (e, stack) {
      AppLogger.error("getCallLogs error", tag: "CALL_CHANNEL", error: e, stackTrace: stack);
      return [];
    }
  }

  Future<bool> requestCallLogPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestCallLogPermission');
      return res ?? false;
    } catch (e) {
      AppLogger.error("requestCallLogPermission error", tag: "CALL_CHANNEL", error: e);
      return false;
    }
  }

  Future<bool> hasCallLogPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('hasCallLogPermission');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Stream<SmsMessageDto> get onSmsReceived {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event == null) throw Exception("Empty event");
      final map = Map<String, dynamic>.from(event as Map);
      AppLogger.info("NativeSmsClient parsed incoming SMS: ${map['address']}", tag: "SMS_CHANNEL");
      return SmsMessageDto(
        address: map['address']?.toString() ?? 'Unknown',
        body: map['body']?.toString() ?? '',
        date: (map['date'] is int)
            ? map['date']
            : DateTime.now().millisecondsSinceEpoch,
        isSent: false,
        subId: map['subId'] is int ? map['subId'] : null,
      );
    });
  }

  Stream<Map<String, dynamic>> get onCallStateChanged {
    return _callEventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event == null) return <String, dynamic>{};
      final map = Map<String, dynamic>.from(event as Map);
      AppLogger.info("NativeSmsClient parsed call event: ${map['state']} for ${map['phoneNumber']}", tag: "CALL_CHANNEL");
      return map;
    });
  }

  Stream<DeviceVolumeDto> get onDeviceStateChanged {
    return _deviceEventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event == null) return const DeviceVolumeDto();
      final map = Map<String, dynamic>.from(event as Map);
      AppLogger.info("NativeSmsClient parsed device state: bt=${map['isBluetoothConnected']}, name=${map['bluetoothDeviceName']}, vol=${map['ringVolume']}", tag: "DEVICE_CHANNEL");
      return DeviceVolumeDto.fromJson(map);
    });
  }

  Future<bool> endPhoneCall() async {
    try {
      AppLogger.info("Invoking endPhoneCall on native channel...", tag: "CALL_CHANNEL");
      final bool? res = await _methodChannel.invokeMethod('endPhoneCall');
      AppLogger.success("endPhoneCall returned $res", tag: "CALL_CHANNEL");
      return res == true;
    } catch (e, stack) {
      AppLogger.error("endPhoneCall error", tag: "CALL_CHANNEL", error: e, stackTrace: stack);
      return false;
    }
  }

  Future<bool> isDefaultSmsApp() async {
    try {
      final bool? res = await _methodChannel.invokeMethod('isDefaultSmsApp');
      return res == true;
    } catch (e, stack) {
      AppLogger.error("Error checking default SMS app", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
      return false;
    }
  }

  Future<bool> requestDefaultSmsApp() async {
    try {
      AppLogger.info("Requesting default SMS app role...", tag: "SMS_CHANNEL");
      final bool? res = await _methodChannel.invokeMethod('requestDefaultSmsApp');
      return res == true;
    } catch (e, stack) {
      AppLogger.error("Error requesting default SMS app", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
      return false;
    }
  }

  Future<List<SimCardDto>> getSimCards() async {
    try {
      AppLogger.info("Invoking getSimCards on native channel...", tag: "SMS_CHANNEL");
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getSimCards',
      );
      if (result == null) {
        AppLogger.info("getSimCards returned null", tag: "SMS_CHANNEL");
        return [];
      }

      final cards = result.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        return SimCardDto(
          subscriptionId: map['subscriptionId'] as int? ?? -1,
          slotIndex: map['slotIndex'] as int? ?? -1,
          carrierName: map['carrierName']?.toString() ?? "Unknown",
        );
      }).toList();
      AppLogger.success("getSimCards found ${cards.length} SIM card(s)", tag: "SMS_CHANNEL");
      return cards;
    } catch (e, stack) {
      AppLogger.error("Error fetching SIMs", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> sendSms(String address, String body, int subId) async {
    try {
      AppLogger.info("Invoking sendSms to $address (subId=$subId)...", tag: "SMS_CHANNEL");
      await _methodChannel.invokeMethod('sendSms', {
        'address': address,
        'body': body,
        'subId': subId,
      });
      AppLogger.success("sendSms successful to $address", tag: "SMS_CHANNEL");
    } catch (e, stack) {
      AppLogger.error("Native send error to $address", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<List<SmsMessageDto>> getMessages({int limit = 50, int offset = 0, String? address}) async {
    try {
      AppLogger.info("Invoking getMessages (limit=$limit, offset=$offset, addr=$address)...", tag: "SMS_CHANNEL");
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getMessages',
        {'limit': limit, 'offset': offset, 'address': address},
      );
      if (result == null) return [];

      final msgs = result.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        return SmsMessageDto(
          id: map['id'] as int?,
          threadId: map['threadId'] as int?,
          address: map['address']?.toString() ?? 'Unknown',
          body: map['body']?.toString() ?? '',
          date: (map['date'] is int)
              ? map['date']
              : DateTime.now().millisecondsSinceEpoch,
          isSent: map['isSent'] == true || map['type'] == 2,
          subId: map['subId'] as int?,
        );
      }).toList();
      AppLogger.success("getMessages returned ${msgs.length} message(s)", tag: "SMS_CHANNEL");
      return msgs;
    } catch (e, stack) {
      AppLogger.error("History fetch error", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<SmsMessageDto>> getThreads({int limit = 50}) async {
    try {
      AppLogger.info("Invoking getThreads (limit=$limit)...", tag: "SMS_CHANNEL");
      final List<dynamic>? result = await _methodChannel.invokeMethod(
        'getThreads',
        {'limit': limit},
      );
      if (result == null) return [];

      final threads = result.map((data) {
        final map = Map<String, dynamic>.from(data as Map);
        return SmsMessageDto(
          id: map['id'] as int?,
          threadId: map['threadId'] as int?,
          address: map['address']?.toString() ?? 'Unknown',
          body: map['body']?.toString() ?? '',
          date: (map['date'] is int) ? map['date'] : DateTime.now().millisecondsSinceEpoch,
          isSent: map['isSent'] == true,
          subId: map['subId'] as int?,
        );
      }).toList();
      AppLogger.success("getThreads returned ${threads.length} thread(s)", tag: "SMS_CHANNEL");
      return threads;
    } catch (e, stack) {
      AppLogger.error("Threads fetch error", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> deleteMessage(int id) async {
    try {
      AppLogger.info("Invoking deleteSms (id=$id)...", tag: "SMS_CHANNEL");
      await _methodChannel.invokeMethod('deleteSms', {'id': id});
    } catch (e, stack) {
      AppLogger.error("deleteMessage error", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
    }
  }

  Future<void> deleteThread(int threadId) async {
    try {
      AppLogger.info("Invoking deleteThread (threadId=$threadId)...", tag: "SMS_CHANNEL");
      await _methodChannel.invokeMethod('deleteThread', {'threadId': threadId});
    } catch (e, stack) {
      AppLogger.error("deleteThread error", tag: "SMS_CHANNEL", error: e, stackTrace: stack);
    }
  }

  Future<DeviceVolumeDto> getDeviceVolume() async {
    try {
      AppLogger.info("Invoking getDeviceVolume...", tag: "VOLUME");
      final result = await _methodChannel.invokeMethod('getDeviceVolume');
      if (result != null) {
        return DeviceVolumeDto.fromJson(Map<String, dynamic>.from(result as Map));
      }
    } catch (e, stack) {
      AppLogger.error("getDeviceVolume error", tag: "VOLUME", error: e, stackTrace: stack);
    }
    return const DeviceVolumeDto();
  }

  Future<DeviceVolumeDto> setDeviceVolume({required String stream, required int volume}) async {
    try {
      AppLogger.info("Invoking setDeviceVolume(stream=$stream, volume=$volume)...", tag: "VOLUME");
      final result = await _methodChannel.invokeMethod('setDeviceVolume', {
        'stream': stream,
        'volume': volume,
      });
      if (result != null) {
        return DeviceVolumeDto.fromJson(Map<String, dynamic>.from(result as Map));
      }
    } catch (e, stack) {
      AppLogger.error("setDeviceVolume error", tag: "VOLUME", error: e, stackTrace: stack);
    }
    return const DeviceVolumeDto();
  }

  Future<DeviceVolumeDto> adjustDeviceVolume({required String stream, required String direction}) async {
    try {
      AppLogger.info("Invoking adjustDeviceVolume(stream=$stream, direction=$direction)...", tag: "VOLUME");
      final result = await _methodChannel.invokeMethod('adjustDeviceVolume', {
        'stream': stream,
        'direction': direction,
      });
      if (result != null) {
        return DeviceVolumeDto.fromJson(Map<String, dynamic>.from(result as Map));
      }
    } catch (e, stack) {
      AppLogger.error("adjustDeviceVolume error", tag: "VOLUME", error: e, stackTrace: stack);
    }
    return const DeviceVolumeDto();
  }
}
