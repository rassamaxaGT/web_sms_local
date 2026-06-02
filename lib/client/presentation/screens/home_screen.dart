import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/chat_window.dart';
import '../../../shared/theme.dart';
import 'login_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Sleek WebSocket/HTTP data synchronizer trigger
    ref.watch(syncProvider);

    // 2. Local disconnection auto-recovery
    ref.listen<bool>(isConnectedProvider, (previous, connected) {
      if (previous == true && connected == false) {
        _handleDisconnect(context, ref);
      }
    });

    final selectedChat = ref.watch(selectedChatIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left Sidebar Container
          Container(
            width: 350,
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(right: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: const ChatSidebar(),
          ),
          
          // Right Main Chat Panel
          Expanded(
            child: selectedChat == null
                ? const EmptyChatState()
                : ChatWindow(phone: selectedChat),
          ),
        ],
      ),
    );
  }

  void _handleDisconnect(BuildContext context, WidgetRef ref) {
    ref.read(serverUrlProvider.notifier).set(null);
    ref.read(passwordProvider.notifier).set(null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Связь потеряна. Сервер недоступен.", style: TextStyle(color: Colors.white)),
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
