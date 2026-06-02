import 'package:flutter_test/flutter_test.dart';
import 'package:sms_host_native/sms_host_native.dart';
import 'package:sms_host_native/sms_host_native_platform_interface.dart';
import 'package:sms_host_native/sms_host_native_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSmsHostNativePlatform
    with MockPlatformInterfaceMixin
    implements SmsHostNativePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SmsHostNativePlatform initialPlatform = SmsHostNativePlatform.instance;

  test('$MethodChannelSmsHostNative is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSmsHostNative>());
  });

  test('getPlatformVersion', () async {
    SmsHostNative smsHostNativePlugin = SmsHostNative();
    MockSmsHostNativePlatform fakePlatform = MockSmsHostNativePlatform();
    SmsHostNativePlatform.instance = fakePlatform;

    expect(await smsHostNativePlugin.getPlatformVersion(), '42');
  });
}
