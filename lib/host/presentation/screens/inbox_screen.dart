import 'dart:async';
import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../server/server_manager.dart';
import '../widgets/server_control_panel.dart'; // "Спрятанный" функционал
import 'chat_screen.dart'; // Экран чата

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  // Менеджер сервера живет здесь
  final ServerManager _serverManager = ServerManager();

  List<SmsMessageDto> _messages = [];
  bool _isLoading = true;
  StreamSubscription? _smsSubscription;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initApp() async {
    // 1. Запрос прав
    await [
      Permission.sms,
      Permission.phone,
      Permission.contacts,
      Permission.notification,
      Permission.locationWhenInUse,
    ].request();

    // 2. Загрузка истории
    await _loadMessages();

    // 3. Подписка на новые SMS (чтобы список обновлялся в реальном времени)
    // Доступ к NativeClient через ServerManager (нужно сделать геттер или сделать поле public)
    // Для простоты предполагаем, что у ServerManager есть геттер smsClient
    _smsSubscription = _serverManager.smsClient.onSmsReceived.listen((msg) {
      if (mounted) {
        setState(() {
          _messages.insert(0, msg);
        });
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final msgs = await _serverManager.smsClient.getFullHistory();
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  // Группировка сообщений по номерам для списка диалогов
  Map<String, SmsMessageDto> _getThreads() {
    final Map<String, SmsMessageDto> threads = {};
    // Проходим по сообщениям, сохраняем только последнее для каждого номера
    for (var msg in _messages) {
      if (!threads.containsKey(msg.address)) {
        threads[msg.address] = msg;
      }
    }
    return threads;
  }

  void _openServerControls() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ServerControlPanel(serverManager: _serverManager),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threads = _getThreads();
    final sortedAddresses = threads.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          // КНОПКА СИНХРОНИЗАЦИИ (Спрятанный функционал)
          IconButton(
            icon: const Icon(Icons.phonelink_ring, color: Colors.indigo),
            tooltip: "Sync with Web",
            onPressed: _openServerControls,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMessages,
              child: sortedAddresses.isEmpty
                  ? const Center(child: Text("No messages"))
                  : ListView.builder(
                      itemCount: sortedAddresses.length,
                      itemBuilder: (ctx, i) {
                        final address = sortedAddresses[i];
                        final lastMsg = threads[address]!;

                        // ДОБАВЛЯЕМ DISMISSIBLE ДЛЯ УДАЛЕНИЯ СВАЙПОМ
                        return Dismissible(
                          key: Key(address),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (dir) async {
                            return await showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Delete Chat?"),
                                content: const Text(
                                  "This will delete all messages in this conversation.",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      "Delete",
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (_) async {
                            if (lastMsg.threadId != null) {
                              try {
                                await _serverManager.smsClient.deleteThread(
                                  lastMsg.threadId!,
                                );
                                _loadMessages(); // Перезагружаем список
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Error: Make sure app is Default SMS App",
                                    ),
                                  ),
                                );
                                _loadMessages(); // Возвращаем, если ошибка
                              }
                            }
                          },
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.indigo.shade100,
                              child: const Icon(
                                Icons.person,
                                color: Colors.indigo,
                              ),
                            ),
                            title: Text(
                              address,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              lastMsg.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              _formatDate(lastMsg.date),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    address: address,
                                    serverManager: _serverManager,
                                  ),
                                ),
                              ).then((_) => _loadMessages());
                            },
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Логика создания нового чата (можно добавить позже)
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.message),
      ),
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
