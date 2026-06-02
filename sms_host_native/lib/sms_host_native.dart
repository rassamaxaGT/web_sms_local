
import 'sms_host_native_platform_interface.dart';

class SmsHostNative {
  Future<String?> getPlatformVersion() {
    return SmsHostNativePlatform.instance.getPlatformVersion();
  }
}
