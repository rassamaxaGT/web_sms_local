# Project Brief: SMS Host & Local Web/Desktop Client (`web_sms_local` / `android_host`)

## Overview
`web_sms_local` is a dual-architecture Flutter application that transforms an Android smartphone into a private, self-hosted SMS gateway and broadcast dispatch server. It runs an embedded HTTP/WebSocket server directly on the Android device, allowing local network (Wi-Fi) Web and Windows Desktop clients to send, receive, and manage SMS messages, contact threads, and mass broadcast campaigns in real time without external cloud infrastructure.

## Technology Stack
- **Primary Language**: Dart (Flutter SDK), Kotlin (Android native telephony plugin)
- **Framework / Core Library**: Flutter 3.x (Dart SDK `^3.10.1`)
- **Key Dependencies**:
  - `flutter_riverpod` (`^3.2.0`): Reactive state management for Web and Desktop client interfaces.
  - `shelf`, `shelf_router`, `shelf_web_socket`, `shelf_static`: Embedded HTTP & WebSocket server engine hosted on Android.
  - `sms_host_native` (local path package `./sms_host_native`): Custom Android MethodChannel plugin interfacing with Android `SmsManager`, `SubscriptionManager`, and `TelephonyManager`.
  - `flutter_background_service` (`^5.0.0`) & `flutter_local_notifications` (`^19.5.0`): Persistent Android background service execution and foreground notification daemon.
  - `nsd` (`^4.1.0`): Local network mDNS service discovery (resolving `sms-host.local`).
  - `archive` (`^4.0.7`): Decompresses pre-compiled `web.zip` on Android device to serve the Web UI locally.
  - `mobile_scanner` (`^7.1.4`) & `qr_flutter` (`^4.1.0`): Dynamic QR pairing and authorization between host and clients.
  - `web_socket_channel` (`^3.0.3`) & `http` (`^1.2.0`): Real-time bidirectional client-to-host communication.
  - `crypto` (`^3.0.3`) & `encrypt` (`^5.0.1`): Local auth token hashing and end-to-end payload encryption (AES-CBC).
  - `audioplayers` (`^6.0.0`): Audio feedback for outgoing and incoming messages (`SfxService`).
  - `shared_preferences` (`^2.5.5`): Local client session and preference persistence across restarts.
- **Dev Tools / Utilities**:
  - `flutter_lints` (`^6.0.0`): Code style and static analysis rules.
  - PowerShell / Batch build scripts: [build_and_run.bat](file:///d:/projects/web_sms_local/build_and_run.bat), [build_client_windows.bat](file:///d:/projects/web_sms_local/build_client_windows.bat).

## Project Structure
- `lib/`: Main application source code
  - [main.dart](file:///d:/projects/web_sms_local/lib/main.dart): Entry point for the **Android Host** server application (initializes background service, logger, SFX, and host UI).
  - [main_web.dart](file:///d:/projects/web_sms_local/lib/main_web.dart): Entry point for the **Web Client** (compiled into `web.zip` and served by Android Host).
  - [main_client.dart](file:///d:/projects/web_sms_local/lib/main_client.dart): Entry point for the **Windows Desktop Client** (`.exe`).
  - `host/`: Host server architecture
    - `server/`: Embedded Shelf HTTP & WebSocket router ([http_router.dart](file:///d:/projects/web_sms_local/lib/host/server/http_router.dart)) and server lifecycle manager ([server_manager.dart](file:///d:/projects/web_sms_local/lib/host/server/server_manager.dart)).
    - `service/`: Persistent Android background daemon ([background_service_logic.dart](file:///d:/projects/web_sms_local/lib/host/service/background_service_logic.dart)) and broadcast SMS dispatcher ([broadcast_engine.dart](file:///d:/projects/web_sms_local/lib/host/service/broadcast_engine.dart)).
    - `data/`: Native SMS client interface ([native_sms_client.dart](file:///d:/projects/web_sms_local/lib/host/data/native_sms_client.dart)), campaign storage ([campaign_storage.dart](file:///d:/projects/web_sms_local/lib/host/data/campaign_storage.dart)), contacts ([contact_storage.dart](file:///d:/projects/web_sms_local/lib/host/data/contact_storage.dart)), and message templates ([template_storage.dart](file:///d:/projects/web_sms_local/lib/host/data/template_storage.dart)).
    - `presentation/`: Host UI for configuration, QR code pairing ([qr_scan_screen.dart](file:///d:/projects/web_sms_local/lib/host/presentation/qr_scan_screen.dart)), inbox management ([inbox_screen.dart](file:///d:/projects/web_sms_local/lib/host/presentation/screens/inbox_screen.dart)), chat viewer ([chat_screen.dart](file:///d:/projects/web_sms_local/lib/host/presentation/screens/chat_screen.dart)), and server status panel ([server_control_panel.dart](file:///d:/projects/web_sms_local/lib/host/presentation/widgets/server_control_panel.dart)).
  - `client/`: Client-side interface
    - `logic/`: Riverpod state management & providers ([providers.dart](file:///d:/projects/web_sms_local/lib/client/logic/providers.dart)), network scanner ([network_scanner.dart](file:///d:/projects/web_sms_local/lib/client/logic/network_scanner.dart)), local desktop/web notifications ([notification_service.dart](file:///d:/projects/web_sms_local/lib/client/logic/notification_service.dart)), and scheduled callback alarms ([callback_scheduler.dart](file:///d:/projects/web_sms_local/lib/client/logic/callback_scheduler.dart)).
    - `data/`: REST and WebSocket API communication client with payload encryption ([api_client.dart](file:///d:/projects/web_sms_local/lib/client/data/api_client.dart)).
    - `presentation/`:
      - `screens/`: Login/Pairing screen ([login_screen.dart](file:///d:/projects/web_sms_local/lib/client/presentation/screens/login_screen.dart)), main workspace ([home_screen.dart](file:///d:/projects/web_sms_local/lib/client/presentation/screens/home_screen.dart)), and thread screen ([thread_screen.dart](file:///d:/projects/web_sms_local/lib/client/presentation/screens/thread_screen.dart)).
      - `views/`: Full client card view with notes and history ([client_card_view.dart](file:///d:/projects/web_sms_local/lib/client/presentation/views/client_card_view.dart)), Broadcast Hub ([broadcast_hub_view.dart](file:///d:/projects/web_sms_local/lib/client/presentation/views/broadcast/broadcast_hub_view.dart)), live broadcast monitor ([broadcast_monitor_view.dart](file:///d:/projects/web_sms_local/lib/client/presentation/views/broadcast/broadcast_monitor_view.dart)), campaign creation wizard ([broadcast_wizard_dialog.dart](file:///d:/projects/web_sms_local/lib/client/presentation/views/broadcast/broadcast_wizard_dialog.dart)), and Telephony Call Log & Analytics ([call_log_view.dart](file:///d:/projects/web_sms_local/lib/client/presentation/views/call_log/call_log_view.dart)).
      - `widgets/`: Multi-filter chat sidebar ([chat_sidebar.dart](file:///d:/projects/web_sms_local/lib/client/presentation/widgets/chat_sidebar.dart)), rich chat window with smart linter & quick replies ([chat_window.dart](file:///d:/projects/web_sms_local/lib/client/presentation/widgets/chat_window.dart)), inline date/time picker ([inline_date_time_picker.dart](file:///d:/projects/web_sms_local/lib/client/presentation/widgets/inline_date_time_picker.dart)), bubble component ([message_bubble.dart](file:///d:/projects/web_sms_local/lib/client/presentation/widgets/message_bubble.dart)), and real-time active call indicator ([active_call_bar.dart](file:///d:/projects/web_sms_local/lib/client/presentation/widgets/active_call_bar.dart)).
    - `utils/`: Recipient import parser for CSV/TXT ([recipient_importer.dart](file:///d:/projects/web_sms_local/lib/client/utils/recipient_importer.dart)), GSM-7/UCS-2 SMS segment and part counter ([sms_counter.dart](file:///d:/projects/web_sms_local/lib/client/utils/sms_counter.dart)), and cross-platform web/clipboard helpers.
  - `shared/`: Shared domain models and cross-platform abstractions
    - [shared_models.dart](file:///d:/projects/web_sms_local/lib/shared/shared_models.dart): Data models (`SmsMessageDto`, `SimCardDto`, `SmsTemplateDto`, `ContactDto`, `CallRecordDto`, `CampaignDto`, `CampaignItemDto`, etc.).
    - [security_service.dart](file:///d:/projects/web_sms_local/lib/shared/security_service.dart): PIN authentication and AES payload encryption.
    - [theme.dart](file:///d:/projects/web_sms_local/lib/shared/theme.dart): Design tokens (colors, typography, dark/light themes, sound effects).
    - [app_logger.dart](file:///d:/projects/web_sms_local/lib/shared/app_logger.dart): Persistent rotating file logger with formatted output and log streaming.
    - [storage_helper.dart](file:///d:/projects/web_sms_local/lib/shared/storage_helper.dart): Cross-platform abstraction for persistent preferences (Web `window.localStorage` vs. Desktop/Native `shared_preferences`).
- `sms_host_native/`: Standalone Flutter plugin with native Android Kotlin implementation ([SmsHostNativePlugin.kt](file:///d:/projects/web_sms_local/sms_host_native/android/src/main/kotlin/com/example/sms_host_native/sms_host_native/SmsHostNativePlugin.kt)) interfacing with telephony subsystems (`SmsManager`, multipart SMS, SIM slot detection).
- `assets/`: Static assets including UI sounds (`assets/sounds/`) and pre-bundled `web.zip` web client build.
- [pubspec.yaml](file:///d:/projects/web_sms_local/pubspec.yaml): Root project configuration and dependencies.

## How to Build & Run
- **Install dependencies**:
  ```bash
  flutter pub get
  ```
- **Build Web Client & Run Android Host (Release)**:
  ```bash
  build_and_run.bat
  ```
  *Or manually step-by-step:*
  ```bash
  flutter build web --release --target lib/main_web.dart --base-href / --no-tree-shake-icons
  powershell -command "Compress-Archive -Path 'build\web\*' -DestinationPath 'assets\web.zip' -Force"
  flutter run --release -t lib/main.dart
  ```
- **Run Web Client in Chrome for local development**:
  ```bash
  flutter run -d chrome -t lib/main_web.dart
  ```
- **Build Windows Desktop Client (.exe)**:
  ```bash
  build_client_windows.bat
  ```
  *Or manually:*
  ```bash
  flutter build windows --release --target lib/main_client.dart
  ```
  *The executable is output to: `build\windows\x64\runner\Release\android_host.exe`.*
- **Run tests**:
  ```bash
  flutter test
  cd sms_host_native && flutter test
  ```

## Architecture & Code Patterns
- **Dual-Target Monorepo**: Server (Android Host) and clients (Web & Desktop) live within a single unified codebase, sharing core DTOs, security services, and UI themes.
- **Zero-Cloud Local Gateway**: Uses an embedded `Shelf` HTTP/WebSocket server running on the Android device; clients connect via local Wi-Fi IP or mDNS (`sms-host.local`).
- **Self-Hosted Web UI Bundle**: The Android host serves its own Web UI directly to browsers on the local network by decompressing `assets/web.zip` into its local application directory on launch.
- **Broadcast Campaign Engine**: Background queue engine supporting template variable interpolation (`{name}`, `{code}`), single-SIM or round-robin multi-SIM dispatch, pause/resume, and real-time WebSocket progress telemetry.
- **Real-Time Synchronisation & State Management**: Powered by Riverpod (`flutter_riverpod`) with optimistic UI updates and live synchronization over WebSockets with automated polling fallbacks and smart deduplication.
- **Smart SMS Linting & Anti-Spam Checking**: Embedded rule-based text analysis in the message editor checking for double spaces, improper sentence casing, abbreviation exceptions, and operator spam-trigger keywords.
- **Scheduled Callbacks & Notifications**: Desktop/Web notifications and scheduled callback reminders for customer follow-up.
- **Telephony Monitoring & Call History**: Real-time incoming/outgoing call status bar notifications, call duration timer, dialer/call-log analytics, and automatic contact matching.
- **Native Android Telephony Bridge**: Low-level SMS transmission, multipart SMS support, telephony broadcast receivers, and dual-SIM management handled through the local `sms_host_native` plugin.
- **End-to-End Encryption & Pairing**: REST API payload encryption and session pairing via PIN authentication and QR codes.
