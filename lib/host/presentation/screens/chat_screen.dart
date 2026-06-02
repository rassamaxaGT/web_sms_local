import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import '../../data/native_sms_client.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/theme.dart';

class ChatScreen extends StatefulWidget {
  final String address;

  const ChatScreen({
    super.key,
    required this.address,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final NativeSmsClient _smsClient = NativeSmsClient();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<SmsMessageDto> _messages = [];
  List<SimCardDto> _sims = [];
  int? _selectedSimId;
  bool _isLoading = true;
  late final AnimationController _bgAnimationController;

  @override
  void initState() {
    super.initState();
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
    _loadData();
  }

  @override
  void dispose() {
    _bgAnimationController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final sims = await _smsClient.getSimCards();
    final allMsgs = await _smsClient.getMessages(limit: 500);
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
      await _smsClient.sendSms(
        widget.address,
        text,
        _selectedSimId!,
      );

      _controller.clear();

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
      SfxService.playSent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ошибка отправки: $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.address,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () {
            SfxService.playSent();
            Navigator.pop(context);
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: Stack(
        children: [
          // Solid dark background layer (static)
          Container(color: AppColors.background),
          // Optimized GPU-Accelerated Rotating Mesh Gradient Background
          Positioned.fill(
            child: RepaintBoundary(
              child: RotationTransition(
                turns: _bgAnimationController,
                child: Stack(
                  children: [
                    // Left top steel-violet bubble
                    Positioned(
                      top: -80,
                      left: -80,
                      child: Container(
                        width: 350,
                        height: 350,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x186366F1), // 9% opacity blue-violet
                              Color(0x006366F1),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Right bottom charcoal violet bubble
                    Positioned(
                      bottom: -120,
                      right: -60,
                      child: Container(
                        width: 380,
                        height: 380,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x10818CF8), // 6% opacity lavender
                              Color(0x00818CF8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Outer overlay dot pattern
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: DotPatternPainter()),
            ),
          ),

          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        cacheExtent: 400,
                        itemBuilder: (ctx, i) {
                          final msg = _messages[i];
                          final isMe = msg.isSent;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              decoration: BoxDecoration(
                                color: isMe 
                                    ? AppColors.msgSent.withValues(alpha: 0.18) 
                                    : AppColors.msgReceived.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                border: Border.all(
                                  color: isMe 
                                      ? AppColors.accent.withValues(alpha: 0.35) 
                                      : AppColors.border,
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              child: SelectionArea(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Linkify(
                                      onOpen: (link) async => await launchUrl(Uri.parse(link.url)),
                                      text: msg.body,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                      linkStyle: const TextStyle(
                                        color: AppColors.accentLight,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime(msg.date),
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: AppColors.textSecondary,
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
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.4),
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // SIM switcher popup on mobile
          if (_sims.length > 1) ...[
            PopupMenuButton<int>(
              initialValue: _selectedSimId,
              onSelected: (v) {
                setState(() => _selectedSimId = v);
                SfxService.playSent();
              },
              color: AppColors.cardBgSolid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              itemBuilder: (ctx) => _sims.map((s) => PopupMenuItem(
                value: s.subscriptionId,
                child: Text(
                  "SIM ${s.slotIndex + 1} (${s.carrierName})",
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
              )).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.msgSent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sim_card_rounded, size: 14, color: AppColors.accentLight),
                    const SizedBox(width: 4),
                    Text(
                      "SIM ${(_sims.indexWhere((s) => s.subscriptionId == _selectedSimId) + 1).clamp(1, 2)}",
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.msgReceived.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: "Напишите сообщение...",
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            onPressed: _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ],
      ),
    );
  }
}
