import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/chat_window.dart';
import 'login_screen.dart'; // Импорт для возврата

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Следим за синхронизацией
    ref.watch(syncProvider);

    // 2. СЛУШАЕМ ПОТЕРЮ СОЕДИНЕНИЯ
    ref.listen<bool>(isConnectedProvider, (previous, connected) {
      if (previous == true && connected == false) {
        // Если мы были подключены и связь пропала
        _handleDisconnect(context, ref);
      }
    });

    final selectedChat = ref.watch(selectedChatIdProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Row(
        children: [
          Container(
            width: 350,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.black12)),
            ),
            child: const ChatSidebar(),
          ),
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
    // Останавливаем все процессы
    ref.read(serverUrlProvider.notifier).set(null);
    ref.read(passwordProvider.notifier).set(null);

    // Показываем сообщение
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Связь потеряна. Сервер недоступен."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );

    // Вылетаем на главный экран
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }
}

// Виджет-заглушка: показывается, когда ни один чат не выбран
class EmptyChatState extends StatelessWidget {
  const EmptyChatState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 100,
            color: Colors.grey.withValues(alpha:  0.3),
          ),
          const SizedBox(height: 20),
          Text(
            "Выберите чат, чтобы начать общение",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Все ваши переписки защищены сквозным шифрованием",
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
