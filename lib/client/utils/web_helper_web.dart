import 'package:web/web.dart' as web;

String? getWebHostUrl() {
  try {
    final location = web.window.location;
    final hostname = location.hostname;
    final protocol = location.protocol;
    final host = location.host;

    if (hostname.startsWith("192.168.") || hostname.startsWith("10.")) {
      return "$protocol//$host";
    }
  } catch (_) {
    // Fail-safe
  }
  return null;
}
