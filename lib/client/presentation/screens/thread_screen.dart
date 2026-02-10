import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../widgets/message_bubble.dart';

class ThreadScreen extends ConsumerStatefulWidget {
  final String phone;
  const ThreadScreen({required this.phone, super.key});

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int? _selectedSimId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sims = ref.read(simsProvider);
      if (sims.isNotEmpty) {
        setState(() => _selectedSimId = sims.first.subscriptionId);
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _send() async {
    final txt = _controller.text.trim();
    if (txt.isEmpty || _selectedSimId == null) return;

    final api = ref.read(apiClientProvider);
    try {
      await api?.sendSms(widget.phone, txt, _selectedSimId!);
      _controller.clear();
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    } catch (e) {
     if (!mounted) return; 
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  String? _getSimName(int? subId, List<SimCardDto> sims) {
    if (subId == null) return null;
    try {
      final s = sims.firstWhere((e) => e.subscriptionId == subId);
      return "${s.carrierName} (${s.slotIndex + 1})";
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(threadsProvider);
    final messages = threads[widget.phone] ?? [];
    final sims = ref.watch(simsProvider);

    // Автоскролл при новом сообщении
    ref.listen(threadsProvider, (prev, next) {
      if ((next[widget.phone]?.length ?? 0) >
          (prev?[widget.phone]?.length ?? 0)) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.phone)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (ctx, i) => MessageBubble(
                message: messages[i],
                simName: _getSimName(messages[i].subId, sims),
              ),
            ),
          ),
          _buildInputArea(sims),
        ],
      ),
    );
  }

  Widget _buildInputArea(List<SimCardDto> sims) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          if (sims.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedSimId,
                icon: const Icon(Icons.sim_card),
                items: sims
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.subscriptionId,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            s.carrierName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedSimId = v),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: "Type a message...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
