import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../widgets/chat_sidebar.dart';
import '../views/client_card_view.dart';
import '../views/broadcast/broadcast_hub_view.dart';
import '../views/call_log/call_log_view.dart';
import '../../../shared/theme.dart';
import 'login_screen.dart';

import '../widgets/active_call_bar.dart';
import '../../utils/selection_manager.dart';
import '../../utils/copy_helper.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl && isShift) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _adjustVolume(up: true);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _adjustVolume(up: false);
        return true;
      }
    } else if (isCtrl &&
        !isShift &&
        (event.logicalKey == LogicalKeyboardKey.keyC ||
            event.logicalKey == LogicalKeyboardKey.insert)) {
      if (!isFocusedOnEditableTextWithSelection()) {
        final text = WebSelectionManager.selectedText;
        if (text != null && text.isNotEmpty) {
          copyToClipboard(text);
          return true;
        }
      }
    }
    return false;
  }

  void _adjustVolume({required bool up}) {
    final activeCall = ref.read(activeCallProvider);
    final inCallDialogue = activeCall.isInCall && activeCall.callStatus != 'RINGING';

    if (inCallDialogue) {
      if (up) {
        ref.read(deviceVolumeProvider.notifier).callVolumeUp();
      } else {
        ref.read(deviceVolumeProvider.notifier).callVolumeDown();
      }
    } else {
      if (up) {
        ref.read(deviceVolumeProvider.notifier).ringVolumeUp();
      } else {
        ref.read(deviceVolumeProvider.notifier).ringVolumeDown();
      }
    }
    SfxService.playSent();
    _showVolumeFeedback(inCallDialogue);
  }

  void _showVolumeFeedback(bool inCallDialogue) {
    if (!mounted) return;
    final vol = ref.read(deviceVolumeProvider);
    final isRingingOrIdle = !inCallDialogue;
    final currentVal = isRingingOrIdle ? vol.ringVolume : vol.callVolume;
    final maxVal = isRingingOrIdle ? vol.maxRingVolume : vol.maxCallVolume;
    final percent = maxVal > 0 ? ((currentVal / maxVal) * 100).round() : 0;
    final isMuted = isRingingOrIdle && vol.isMuted;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              inCallDialogue
                  ? Icons.phone_in_talk_rounded
                  : (isMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded),
              color: isMuted ? AppColors.warning : AppColors.accentLight,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                inCallDialogue
                    ? "Громкость разговора: $currentVal/$maxVal ($percent%)"
                    : "Громкость звонка: $currentVal/$maxVal ($percent%)",
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        width: 320,
        backgroundColor: AppColors.cardBgSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Sleek WebSocket/HTTP data synchronizer trigger
    ref.watch(syncProvider);

    // 2. Local disconnection auto-recovery
    ref.listen<bool>(isConnectedProvider, (previous, connected) {
      if (previous == true && connected == false) {
        _handleDisconnect(context, ref);
      }
    });

    final viewMode = ref.watch(activeViewModeProvider);
    final selectedChat = ref.watch(selectedChatIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SelectionArea(
        onSelectionChanged: WebSelectionManager.onSelectionChanged,
        child: Column(
          children: [
            const ActiveCallBar(),
            Expanded(
              child: Row(
                children: [
                  // Left Sidebar Container
                  Container(
                    width: 350,
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      border: Border(
                        right: BorderSide(color: AppColors.border, width: 1),
                      ),
                    ),
                    child: const ChatSidebar(),
                  ),

                  // Right Main Panel
                  Expanded(
                    child: viewMode == AppViewMode.broadcast
                        ? const BroadcastHubView()
                        : viewMode == AppViewMode.callLog
                            ? const CallLogView()
                            : selectedChat == null
                                ? const EmptyChatState()
                                : ClientCardView(phone: selectedChat),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDisconnect(BuildContext context, WidgetRef ref) {
    ref.read(serverUrlProvider.notifier).set(null);
    ref.read(passwordProvider.notifier).set(null);
    ref.read(allMessagesProvider.notifier).set([]);
    ref.read(simsProvider.notifier).set([]);
    ref.read(selectedChatIdProvider.notifier).select(null);
    ref.read(selectedSimProvider.notifier).set(null);
    ref.read(searchQueryProvider.notifier).set("");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Связь потеряна. Сервер недоступен.",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 5),
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }
}

// Beautiful Empty state shown when no chat is active
class EmptyChatState extends StatelessWidget {
  const EmptyChatState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Elegant dot pattern backdrop
          const Positioned.fill(
            child: CustomPaint(painter: DotPatternPainter()),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.msgSent.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 64,
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Выберите чат для начала общения",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      fontFamily: 'Outfit',
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Все ваши SMS-переписки защищены сквозным локальным шифрованием.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
