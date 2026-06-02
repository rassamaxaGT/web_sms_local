import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sms_host_native_method_channel.dart';

abstract class SmsHostNativePlatform extends PlatformInterface {
  /// Constructs a SmsHostNativePlatform.
  SmsHostNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static SmsHostNativePlatform _instance = MethodChannelSmsHostNative();

  /// The default instance of [SmsHostNativePlatform] to use.
  ///
  /// Defaults to [MethodChannelSmsHostNative].
  static SmsHostNativePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SmsHostNativePlatform] when
  /// they register themselves.
  static set instance(SmsHostNativePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
