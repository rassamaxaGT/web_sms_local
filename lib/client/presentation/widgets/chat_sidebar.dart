import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';

class ChatSidebar extends ConsumerWidget {
  const ChatSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(filteredThreadsProvider);
    final selectedId = ref.watch(selectedChatIdProvider);
    // Подписываемся на счетчики непрочитанных
    final unreadCounts = ref.watch(unreadCountsProvider);

    final sortedNumbers = threads.keys.toList()
      ..sort((a, b) => threads[b]!.last.date.compareTo(threads[a]!.last.date));

    return Column(
      children: [
        // Заголовок и поиск
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    "Сообщения",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: () => _showNewChatDialog(context, ref),
                    icon: const Icon(Icons.edit_note_rounded),
                    tooltip: "Новый чат",
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (val) {
                  ref.read(searchQueryProvider.notifier).set(val);
                },
                decoration: InputDecoration(
                  hintText: "Поиск...",
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, indent: 16, endIndent: 16),

        // Список чатов
        Expanded(
          child: sortedNumbers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Ничего не найдено",
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sortedNumbers.length,
                  itemBuilder: (ctx, i) {
                    final phone = sortedNumbers[i];
                    final lastMsg = threads[phone]!.last;
                    final isSelected = phone == selectedId;
                    
                    // Получаем количество непрочитанных
                    final unreadCount = unreadCounts[phone] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: InkWell(
                        onTap: () {
                          // 1. Выбираем чат
                          ref.read(selectedChatIdProvider.notifier).select(phone);
                          // 2. Сбрасываем счетчик непрочитанных
                          ref.read(unreadCountsProvider.notifier).clear(phone);
                        },
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.indigo.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors
                                    .primaries[phone.hashCode %
                                        Colors.primaries.length]
                                    .withValues(alpha: 0.2),
                                child: Text(
                                  phone.isNotEmpty
                                      ? phone
                                            .replaceAll('+', '')
                                            .substring(0, 1)
                                            .toUpperCase()
                                      : "?",
                                  style: TextStyle(
                                    color:
                                        Colors.primaries[phone.hashCode %
                                            Colors.primaries.length],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            phone,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDate(lastMsg.date),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: unreadCount > 0 
                                                ? Colors.indigo 
                                                : Colors.grey,
                                            fontWeight: unreadCount > 0 
                                                ? FontWeight.bold 
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            lastMsg.body,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: unreadCount > 0 
                                                  ? Colors.black87 
                                                  : Colors.grey.shade600,
                                              fontSize: 14,
                                              fontWeight: unreadCount > 0 
                                                  ? FontWeight.w500 
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        // ИНДИКАТОР НЕПРОЧИТАННЫХ
                                        if (unreadCount > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              unreadCount.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    }
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}";
  }

  void _showNewChatDialog(BuildContext context, WidgetRef ref) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Новое сообщение"),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: "Номер телефона",
            hintText: "+7...",
          ),
          keyboardType: TextInputType.phone,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () {
              if (c.text.isNotEmpty) {
                Navigator.pop(ctx);
                ref.read(selectedChatIdProvider.notifier).select(c.text);
                ref.read(searchQueryProvider.notifier).set("");
              }
            },
            child: const Text("Открыть чат"),
          ),
        ],
      ),
    );
  }
}