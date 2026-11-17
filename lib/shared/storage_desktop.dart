import 'package:shared_preferences/shared_preferences.dart';

SharedPreferences? _prefs;

Future<void> initDesktopStorage() async {
  try {
    _prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Fail-safe: leave _prefs as null, storage calls will degrade gracefully
  }
}

bool getSoundEnabled() {
  return _prefs?.getBool('sound_effects_enabled') ?? false;
}

void setSoundEnabled(bool enabled) {
  _prefs?.setBool('sound_effects_enabled', enabled);
}

String? getDraft(String phone) {
  return _prefs?.getString('draft_$phone');
}

void setDraft(String phone, String text) {
  if (text.isEmpty) {
    _prefs?.remove('draft_$phone');
  } else {
    _prefs?.setString('draft_$phone', text);
  }
}
