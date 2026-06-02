import 'dart:async';
import 'package:android_host/shared/shared_models.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/native_sms_client.dart';
import '../../../shared/theme.dart';
import '../widgets/server_control_panel.dart';
import 'chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with SingleTickerProviderStateMixin {
  final NativeSmsClient _smsClient = NativeSmsClient();

  List<SmsMessageDto> _messages = [];
  bool _isLoading = true;
  StreamSubscription? _smsSubscription;
  late final AnimationController _bgAnimationController;

  @override
  void initState() {
    super.initState();
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
    _initApp();
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    _bgAnimationController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    // 1. Request SMS + Phone + Contacts + Notifications permissions
    await [
      Permission.sms,
      Permission.phone,
      Permission.contacts,
      Permission.notification,
    ].request();

    // 2. Load History
    await _loadMessages();

    // 3. Subscribe to real-time incoming SMS
    _smsSubscription = _smsClient.onSmsReceived.listen((msg) {
      if (mounted) {
        setState(() {
          _messages.insert(0, msg);
        });
        SfxService.playReceived();
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final msgs = await _smsClient.getMessages(limit: 100);
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  Map<String, SmsMessageDto> _getThreads() {
    final Map<String, SmsMessageDto> threads = {};
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
      builder: (ctx) => const ServerControlPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threads = _getThreads();
    final sortedAddresses = threads.keys.toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "СООБЩЕНИЯ",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontFamily: 'Outfit',
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        actions: [
          // Elegant physical link icon to bring up sync panel
          IconButton(
            icon: const Icon(Icons.wifi_tethering_rounded, color: AppColors.accentLight, size: 22),
            tooltip: "Панель управления трансляцией",
            onPressed: () {
              _openServerControls();
              SfxService.playSent();
            },
            style: IconButton.styleFrom(
              backgroundColor: AppColors.msgSent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 14),
        ],
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
                      top: -100,
                      left: -100,
                      child: Container(
                        width: 380,
                        height: 380,
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
                      bottom: -150,
                      right: -80,
                      child: Container(
                        width: 420,
                        height: 420,
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

          // Body Content
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMessages,
                  color: AppColors.accent,
                  backgroundColor: AppColors.cardBgSolid,
                  child: sortedAddresses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 64,
                                color: AppColors.textSecondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "Список диалогов пуст",
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          itemCount: sortedAddresses.length,
                          cacheExtent: 300,
                          addRepaintBoundaries: true,
                          itemBuilder: (ctx, i) {
                            final address = sortedAddresses[i];
                            final lastMsg = threads[address]!;

                            // UniqueDeterministic sleek graphite linear gradient based on contact string hash
                            final startColor = Color((address.hashCode * 0xFF7A) | 0xFF000000).withValues(alpha: 0.85);
                            final endColor = Color((address.hashCode * 0x33B1) | 0xFF000000).withValues(alpha: 0.85);

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Dismissible(
                                key: Key(address),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0x33EF4444), AppColors.error],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.delete_sweep_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                confirmDismiss: (dir) async {
                                  SfxService.playSent();
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: AppColors.cardBgSolid,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      title: const Text(
                                        "Удалить чат?",
                                        style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                                      ),
                                      content: const Text(
                                        "Вся история переписки с этим абонентом будет стерта.",
                                        style: TextStyle(color: AppColors.textSecondary),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text("Отмена", style: TextStyle(color: AppColors.textSecondary)),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.error,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text("Удалить"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                onDismissed: (_) async {
                                  if (lastMsg.threadId != null) {
                                    try {
                                      await _smsClient.deleteThread(lastMsg.threadId!);
                                      SfxService.playSuccess();
                                      _loadMessages();
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Ошибка удаления: системные ограничения SMS"),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                      _loadMessages();
                                    }
                                  }
                                },
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      SfxService.playSent();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(address: address),
                                        ),
                                      ).then((_) => _loadMessages());
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppColors.cardBgSolid.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          // Custom Premium Gradient Avatar
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [startColor, endColor],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              border: Border.all(color: Colors.white10, width: 1),
                                            ),
                                            child: Center(
                                              child: Text(
                                                address.isNotEmpty
                                                    ? address
                                                          .replaceAll('+', '')
                                                          .substring(0, 1)
                                                          .toUpperCase()
                                                    : "?",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          
                                          // Chat Details
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        address,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14.5,
                                                          color: AppColors.textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _formatDate(lastMsg.date),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  lastMsg.body,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Future new conversation trigger
          SfxService.playSent();
        },
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add_comment_rounded),
      ),
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
