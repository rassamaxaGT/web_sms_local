import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import 'message_bubble.dart';

class ChatWindow extends ConsumerStatefulWidget {
  final String phone;
  const ChatWindow({required this.phone, super.key});

  @override
  ConsumerState<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends ConsumerState<ChatWindow> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initSim();
    _scrollToBottom(immediate: true);
  }

  @override
  void didUpdateWidget(covariant ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phone != widget.phone) {
      _initSim();
      _scrollToBottom(immediate: true);
    }
  }

  void _initSim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sims = ref.read(simsProvider);
      final currentSelected = ref.read(selectedSimProvider);

      // Если в списке есть симки, а у нас еще ничего не выбрано — ставим первую
      if (sims.isNotEmpty && currentSelected == null) {
        ref.read(selectedSimProvider.notifier).set(sims.first.subscriptionId);
      }
    });
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _send() async {
    final txt = _controller.text.trim();
    final selectedSimId = ref.read(selectedSimProvider); // Берем из провайдера

    if (txt.isEmpty || selectedSimId == null) return;

    final api = ref.read(apiClientProvider);
    _controller.clear();

    try {
      await api?.sendSms(widget.phone, txt, selectedSimId);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    }
  }

  // Остальные вспомогательные методы (даты) остаются без изменений
  bool _isSameDay(int ms1, int ms2) =>
      DateTime.fromMillisecondsSinceEpoch(ms1).day ==
      DateTime.fromMillisecondsSinceEpoch(ms2).day;

  String _formatDateLabel(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return "Сегодня";
    }
    return "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(threadsProvider);
    final messages = threads[widget.phone] ?? [];
    final sims = ref.watch(simsProvider);
    final selectedSimId = ref.watch(
      selectedSimProvider,
    ); // Следим за выбранной симкой
    final int? currentThreadId = messages.isNotEmpty
        ? messages.first.threadId
        : null;

    ref.listen(threadsProvider, (prev, next) {
      if ((next[widget.phone]?.length ?? 0) >
          (prev?[widget.phone]?.length ?? 0)) {
        _scrollToBottom();
      }
    });

    return Container(
      color: const Color(0xFFF0F2F5),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  child: const Icon(Icons.person, color: Colors.indigo),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.phone,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const Text(
                        "Мобильный",
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (currentThreadId != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _deleteThread(currentThreadId),
                  ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                itemCount: messages.length,
                itemBuilder: (ctx, i) {
                  final msg = messages[i];
                  bool showDate =
                      i == 0 || !_isSameDay(messages[i - 1].date, msg.date);
                  return Column(
                    children: [
                      if (showDate)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha:  0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _formatDateLabel(msg.date),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      MessageBubble(
                        message: msg,
                        simName: _getSimName(msg.subId, sims),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            child: Row(
              children: [
                if (sims.isNotEmpty) _buildSimPicker(sims, selectedSimId),
                const SizedBox(width: 15),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 1,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Введите сообщение...",
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(backgroundColor: Colors.indigo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimPicker(List<SimCardDto> sims, int? selectedId) {
    return PopupMenuButton<int>(
      onSelected: (id) => ref
          .read(selectedSimProvider.notifier)
          .set(id), // Сохраняем в провайдер
      tooltip: "Выбрать SIM",
      itemBuilder: (ctx) => sims
          .map(
            (s) => PopupMenuItem(
              value: s.subscriptionId,
              child: Text("SIM ${s.slotIndex + 1} (${s.carrierName})"),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(Icons.sim_card_outlined, size: 18, color: Colors.indigo),
            const SizedBox(width: 5),
            Text(
              "SIM ${_getSimSlot(selectedId, sims)}",
              style: const TextStyle(
                color: Colors.indigo,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSimSlot(int? id, List<SimCardDto> sims) {
    if (id == null) return "?";
    final s = sims.where((e) => e.subscriptionId == id);
    return s.isNotEmpty ? (s.first.slotIndex + 1).toString() : "1";
  }

  String? _getSimName(int? id, List<SimCardDto> sims) {
    if (id == null) return null;
    final s = sims.where((e) => e.subscriptionId == id);
    return s.isNotEmpty ? s.first.carrierName : null;
  }

  Future<void> _deleteThread(int threadId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Удалить чат?"),
        content: const Text(
          "Эта переписка будет навсегда удалена с вашего телефона.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(apiClientProvider)?.deleteThread(threadId);
      ref.read(selectedChatIdProvider.notifier).select(null);
      ref.invalidate(syncProvider);
    }
  }
}
