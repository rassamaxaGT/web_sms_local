import 'package:web/web.dart' as web;

/// Web-specific storage implementation using window.localStorage.
bool getSoundEnabled() {
  try {
    final savedValue = web.window.localStorage.getItem('sound_effects_enabled');
    return savedValue == 'true';
  } catch (_) {
    return false;
  }
}

void setSoundEnabled(bool enabled) {
  try {
    web.window.localStorage.setItem('sound_effects_enabled', enabled.toString());
  } catch (_) {}
}

String? getDraft(String phone) {
  try {
    return web.window.localStorage.getItem('draft_$phone');
  } catch (_) {
    return null;
  }
}

void setDraft(String phone, String text) {
  try {
    if (text.isEmpty) {
      web.window.localStorage.removeItem('draft_$phone');
    } else {
      web.window.localStorage.setItem('draft_$phone', text);
    }
  } catch (_) {}
}
