/// Stub storage implementation for non-web platforms.
Future<void> initDesktopStorage() async {}

bool getSoundEnabled() => false;
void setSoundEnabled(bool enabled) {}

String? getDraft(String phone) => null;
void setDraft(String phone, String text) {}
