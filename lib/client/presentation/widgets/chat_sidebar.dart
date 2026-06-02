import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_host/shared/shared_models.dart';
import '../../logic/providers.dart';
import '../../../shared/theme.dart';

class ChatSidebar extends ConsumerStatefulWidget {
  const ChatSidebar({super.key});

  @override
  ConsumerState<ChatSidebar> createState() => _ChatSidebarState();
}

enum SidebarTab { all, callback }

class _ChatSidebarState extends ConsumerState<ChatSidebar> {
  String? _hoveredPhone;
  SidebarTab _selectedTab = SidebarTab.all;
  Timer? _callbackRefreshTimer;

  @override
  void initState() {
    super.initState();
    _callbackRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _callbackRefreshTimer?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(filteredThreadsProvider);
    final selectedId = ref.watch(selectedChatIdProvider);
    final unreadCounts = ref.watch(unreadCountsProvider);
    final contacts = ref.watch(contactsProvider);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // Dynamic filtering helper for callbacks that should appear today or are overdue
    bool isPendingCallback(ContactDto c) {
      if (c.callbackTimeMs == null) return false;
      final cbTime = c.callbackTime!;
      return cbTime.isBefore(now) || (cbTime.isAfter(todayStart) && cbTime.isBefore(todayEnd));
    }

    // Calculate pending callbacks
    final callbackCount = contacts.where(isPendingCallback).length;

    var sortedNumbers = threads.keys.toList()
      ..sort((a, b) => threads[b]!.last.date.compareTo(threads[a]!.last.date));

    if (_selectedTab == SidebarTab.callback) {
      final callbackPhones = contacts
          .where(isPendingCallback)
          .map((c) => c.phone)
          .toSet();

      sortedNumbers = sortedNumbers.where((phone) => callbackPhones.contains(phone)).toList();
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Elegant Glassmorphic Header & Search
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      "ЧАТЫ",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontFamily: 'Outfit',
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    
                    // Sound Effects Toggle Button
                    Tooltip(
                      message: SfxService.isSoundEnabled ? "Звук включен" : "Звук выключен",
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            SfxService.toggleSound(!SfxService.isSoundEnabled);
                          });
                          SfxService.playSent();
                        },
                        icon: Icon(
                          SfxService.isSoundEnabled 
                              ? Icons.volume_up_rounded 
                              : Icons.volume_off_rounded,
                          color: SfxService.isSoundEnabled 
                              ? AppColors.success 
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.msgSent,
                          hoverColor: AppColors.accent.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // New Chat Button
                    Tooltip(
                      message: "Новый чат",
                      child: IconButton(
                        onPressed: () => _showNewChatDialog(context, ref),
                        icon: const Icon(Icons.add_comment_rounded, color: AppColors.textPrimary, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          hoverColor: AppColors.accent.withValues(alpha: 0.8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                
                // Beautiful Search Bar
                TextField(
                  onChanged: (val) {
                    ref.read(searchQueryProvider.notifier).set(val);
                  },
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Поиск по номеру...",
                    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 18),
                    filled: true,
                    fillColor: Colors.black12,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Premium Glassmorphic Selector Tabs
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      // Tab "Все"
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTab = SidebarTab.all;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == SidebarTab.all
                                  ? AppColors.accent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _selectedTab == SidebarTab.all
                                  ? [
                                      BoxShadow(
                                        color: AppColors.accent.withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              "Все чаты",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _selectedTab == SidebarTab.all
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Tab "Перезвонить"
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTab = SidebarTab.callback;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == SidebarTab.callback
                                  ? AppColors.accent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _selectedTab == SidebarTab.callback
                                  ? [
                                      BoxShadow(
                                        color: AppColors.accent.withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Перезвонить",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedTab == SidebarTab.callback
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (callbackCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _selectedTab == SidebarTab.callback
                                          ? Colors.white
                                          : AppColors.warning,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "$callbackCount",
                                      style: TextStyle(
                                        color: _selectedTab == SidebarTab.callback
                                            ? AppColors.accent
                                            : Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppColors.border, height: 1),
          ),

          // Chat List
          Expanded(
            child: sortedNumbers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 40,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Список пуст",
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    itemCount: sortedNumbers.length,
                    itemBuilder: (ctx, i) {
                      final phone = sortedNumbers[i];
                      final contact = contacts.firstWhere(
                        (c) => c.phone == phone,
                        orElse: () => ContactDto(phone: phone, name: "", notes: ""),
                      );
                      final lastMsg = threads[phone]!.last;
                      final isSelected = phone == selectedId;
                      final unreadCount = unreadCounts[phone] ?? 0;
                      final isHovered = _hoveredPhone == phone;

                      // Unique, deterministic sleek graphite avatar gradient based on phone number
                      final startColor = Color((phone.hashCode * 0xFF7A) | 0xFF000000).withValues(alpha: 0.85);
                      final endColor = Color((phone.hashCode * 0x33B1) | 0xFF000000).withValues(alpha: 0.85);

                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoveredPhone = phone),
                        onExit: (_) => setState(() => _hoveredPhone = null),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.msgSent.withValues(alpha: 0.65)
                                : isHovered
                                    ? AppColors.cardBg.withValues(alpha: 0.3)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accent.withValues(alpha: 0.3)
                                  : isHovered
                                      ? AppColors.border
                                      : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              ref.read(selectedChatIdProvider.notifier).select(phone);
                              ref.read(unreadCountsProvider.notifier).clear(phone);
                              SfxService.playSent();
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Sleek Avatar with Gradient
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [startColor, endColor],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      border: Border.all(
                                        color: isSelected 
                                            ? AppColors.accent.withValues(alpha: 0.5) 
                                            : Colors.white10,
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        contact.name.isNotEmpty
                                            ? contact.name.substring(0, 1).toUpperCase()
                                            : (phone.isNotEmpty
                                                ? phone
                                                      .replaceAll('+', '')
                                                      .substring(0, 1)
                                                      .toUpperCase()
                                                : "?"),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  
                                  // Details Section
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                contact.name.isNotEmpty ? contact.name : phone,
                                                style: TextStyle(
                                                  fontWeight: isSelected 
                                                      ? FontWeight.bold 
                                                      : FontWeight.w600,
                                                  fontSize: 14,
                                                  color: isSelected 
                                                      ? AppColors.textPrimary 
                                                      : AppColors.textPrimary.withValues(alpha: 0.9),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatDate(lastMsg.date),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: unreadCount > 0 
                                                    ? AppColors.success 
                                                    : AppColors.textSecondary.withValues(alpha: 0.7),
                                                fontWeight: unreadCount > 0 
                                                    ? FontWeight.bold 
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (contact.name.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            phone,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                         if (contact.callbackTime != null) ...[
                                           const SizedBox(height: 4),
                                           Row(
                                             children: [
                                               Icon(
                                                 Icons.phone_callback_rounded,
                                                 size: 11,
                                                 color: contact.callbackTime!.isBefore(now)
                                                     ? AppColors.error
                                                     : AppColors.warning,
                                               ),
                                               const SizedBox(width: 4),
                                               Text(
                                                 contact.callbackTime!.isBefore(now)
                                                     ? "Пропущен в ${_formatTime(contact.callbackTime!)}"
                                                     : "Перезвонить в ${_formatTime(contact.callbackTime!)}",
                                                 style: TextStyle(
                                                   fontSize: 10,
                                                   color: contact.callbackTime!.isBefore(now)
                                                       ? AppColors.error
                                                       : AppColors.warning,
                                                   fontWeight: FontWeight.bold,
                                                 ),
                                               ),
                                             ],
                                           ),
                                         ],
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                lastMsg.body,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: unreadCount > 0 
                                                      ? AppColors.textPrimary 
                                                      : AppColors.textSecondary,
                                                  fontSize: 12.5,
                                                  fontWeight: unreadCount > 0 
                                                      ? FontWeight.w600 
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            
                                            // Slick modern notification counter
                                            if (unreadCount > 0)
                                              Container(
                                                margin: const EdgeInsets.only(left: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.success,
                                                  borderRadius: BorderRadius.circular(10),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.success.withValues(alpha: 0.3),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  unreadCount.toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setState) {
            void validateAndSubmit() {
              final rawInput = c.text.trim();
              if (rawInput.isEmpty) {
                setState(() {
                  errorText = "Введите номер телефона";
                });
                return;
              }

              // Normalize: remove spaces, dashes, parentheses
              final clean = rawInput.replaceAll(RegExp(r'[\s\-()]+'), '');

              // Check if valid format: starts with optionally a +, followed by only digits, length 3 to 15
              final phoneRegex = RegExp(r'^\+?[0-9]{3,15}$');
              if (!phoneRegex.hasMatch(clean)) {
                setState(() {
                  errorText = "Неверный формат номера";
                });
                return;
              }

              // If valid, submit
              Navigator.pop(ctx);
              ref.read(selectedChatIdProvider.notifier).select(clean);
              ref.read(searchQueryProvider.notifier).set("");
              SfxService.playSuccess();
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Новое сообщение"),
              content: TextField(
                controller: c,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (val) {
                  if (errorText != null) {
                    setState(() {
                      errorText = null; // Clear error reactively on type
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: "Номер телефона",
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  hintText: "+7...",
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  errorText: errorText,
                  errorStyle: const TextStyle(color: AppColors.error),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                  errorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.error)),
                  focusedErrorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.error)),
                ),
                keyboardType: TextInputType.phone,
                autofocus: true,
                onSubmitted: (_) => validateAndSubmit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Отмена", style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: validateAndSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Открыть чат"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}