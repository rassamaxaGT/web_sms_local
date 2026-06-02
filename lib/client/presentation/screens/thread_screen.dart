import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../widgets/message_bubble.dart';
import '../../../shared/theme.dart';

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
      SfxService.playSent();
    } catch (e) {
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ошибка: $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.error,
        ),
      );
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

    ref.listen(threadsProvider, (prev, next) {
      if ((next[widget.phone]?.length ?? 0) >
          (prev?[widget.phone]?.length ?? 0)) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.phone,
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
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: DotPatternPainter()),
                ),
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) => MessageBubble(
                    message: messages[i],
                    simName: _getSimName(messages[i].subId, sims),
                  ),
                ),
              ],
            ),
          ),
          _buildInputArea(sims),
        ],
      ),
    );
  }

  Widget _buildInputArea(List<SimCardDto> sims) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          if (sims.isNotEmpty) ...[
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedSimId,
                dropdownColor: AppColors.cardBgSolid,
                icon: const Icon(Icons.sim_card_rounded, color: AppColors.accentLight, size: 18),
                items: sims
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.subscriptionId,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            s.carrierName,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedSimId = v);
                  SfxService.playSent();
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.msgReceived,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: "SMS...",
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
            onPressed: _send,
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
