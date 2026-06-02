import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sms_host_native_platform_interface.dart';

/// An implementation of [SmsHostNativePlatform] that uses method channels.
class MethodChannelSmsHostNative extends SmsHostNativePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sms_host_native');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
