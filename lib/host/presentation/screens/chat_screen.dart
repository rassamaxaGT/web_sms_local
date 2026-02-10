import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import '../../server/server_manager.dart';
import 'package:flutter_linkify/flutter_linkify.dart'; // Добавить
import 'package:url_launcher/url_launcher.dart';    // Добавить

class ChatScreen extends StatefulWidget {
  final String address;
  final ServerManager serverManager;

  const ChatScreen({
    super.key,
    required this.address,
    required this.serverManager,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<SmsMessageDto> _messages = [];
  List<SimCardDto> _sims = [];
  int? _selectedSimId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // 1. Загружаем симки
    final sims = await widget.serverManager.smsClient.getSimCards();

    // 2. Загружаем историю
    final allMsgs = await widget.serverManager.smsClient.getFullHistory();
    // Фильтруем только для этого чата и сортируем
    final chatMsgs = allMsgs.where((m) => m.address == widget.address).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (mounted) {
      setState(() {
        _sims = sims;
        if (_sims.isNotEmpty) _selectedSimId = _sims.first.subscriptionId;
        _messages = chatMsgs;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _selectedSimId == null) return;

    try {
      await widget.serverManager.smsClient.sendSms(
        widget.address,
        text,
        _selectedSimId!,
      );

      _controller.clear();

      // Добавляем сообщение локально для быстрого UI
      setState(() {
        _messages.add(
          SmsMessageDto(
            address: widget.address,
            body: text,
            date: DateTime.now().millisecondsSinceEpoch,
            isSent: true,
            subId: _selectedSimId,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.address),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[i];
                      return Align(
                        alignment: msg.isSent
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: msg.isSent
                                ? Colors.indigo
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: SelectionArea(
                            // Добавляем возможность выделения
                            child: Linkify(
                              onOpen: (link) async =>
                                  await launchUrl(Uri.parse(link.url)),
                              text: msg.body,
                              style: TextStyle(
                                color: msg.isSent ? Colors.white : Colors.black,
                              ),
                              linkStyle: TextStyle(
                                color: msg.isSent ? Colors.amber : Colors.blue,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          if (_sims.length > 1)
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedSimId,
                items: _sims
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.subscriptionId,
                        child: Text(
                          "SIM ${s.slotIndex + 1}",
                          style: const TextStyle(fontSize: 12),
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
                hintText: "SMS...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.indigo),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
