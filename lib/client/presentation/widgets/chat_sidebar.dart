import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_host/shared/shared_models.dart';
import '../../logic/providers.dart';
import '../../utils/recipient_importer.dart';
import '../../../shared/theme.dart';
import '../views/contractor/contractor_lookup_dialog.dart';

class ChatSidebar extends ConsumerStatefulWidget {
  const ChatSidebar({super.key});

  @override
  ConsumerState<ChatSidebar> createState() => _ChatSidebarState();
}

class SidebarListItem {
  final bool isHeader;
  final String? headerText;
  final SidebarClientItem? clientItem;
  SidebarListItem({required this.isHeader, this.headerText, this.clientItem});
}

enum SidebarTab { all, newest, callback }

class PhoneAutoPrefixFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final cleaned = text.replaceAll(RegExp(r'[\s\-\(\)]+'), '');

    if (cleaned.startsWith('7') && !text.startsWith('+')) {
      final formatted = '+$text';
      final newOffset = (newValue.selection.end + 1).clamp(0, formatted.length);
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: newOffset),
      );
    } else if (cleaned.startsWith('8') && !text.startsWith('+')) {
      final firstEight = text.indexOf('8');
      if (firstEight != -1) {
        final formatted = text.replaceRange(firstEight, firstEight + 1, '+7');
        final newOffset = (newValue.selection.end + 1).clamp(0, formatted.length);
        return TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      }
    }

    return newValue;
  }
}

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
    final clients = ref.watch(filteredSidebarClientsProvider);
    final selectedId = ref.watch(selectedChatIdProvider);
    final contacts = ref.watch(contactsProvider);
    final unreadCounts = ref.watch(unreadCountsProvider);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // Dynamic filtering helper for callbacks that should appear today or are overdue
    bool isPendingCallback(ContactDto? c) {
      if (c == null || c.callbackTimeMs == null) return false;
      final cbTime = c.callbackTime!;
      return cbTime.isBefore(now) || (cbTime.isAfter(todayStart) && cbTime.isBefore(todayEnd));
    }

    // Calculate pending callbacks
    final callbackCount = contacts.where((c) => isPendingCallback(c)).length;

    // Total unread messages
    final unreadTotal = unreadCounts.values.fold<int>(0, (sum, count) => sum + count);

    final listItems = <SidebarListItem>[];

    if (_selectedTab == SidebarTab.all) {
      listItems.addAll(clients.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
    } else if (_selectedTab == SidebarTab.newest) {
      final unreadList = <SidebarClientItem>[];
      final otherList = <SidebarClientItem>[];

      for (var c in clients) {
        if (c.unreadCount > 0) {
          unreadList.add(c);
        } else {
          otherList.add(c);
        }
      }

      // Sort unread: newest last message timestamp first
      unreadList.sort((a, b) {
        if (a.lastMessage != null && b.lastMessage != null) {
          return b.lastMessage!.date.compareTo(a.lastMessage!.date);
        } else if (a.lastMessage != null) {
          return -1;
        } else if (b.lastMessage != null) {
          return 1;
        }
        return (a.contact?.name ?? a.phone).compareTo(b.contact?.name ?? b.phone);
      });

      // Sort remaining chats: newest last message timestamp first, then contacts
      otherList.sort((a, b) {
        if (a.lastMessage != null && b.lastMessage != null) {
          return b.lastMessage!.date.compareTo(a.lastMessage!.date);
        } else if (a.lastMessage != null) {
          return -1;
        } else if (b.lastMessage != null) {
          return 1;
        }
        final nameA = a.contact?.name ?? '';
        final nameB = b.contact?.name ?? '';
        if (nameA.isNotEmpty || nameB.isNotEmpty) {
          if (nameA.isEmpty) return 1;
          if (nameB.isEmpty) return -1;
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        }
        return a.phone.compareTo(b.phone);
      });

      if (unreadList.isNotEmpty) {
        listItems.add(SidebarListItem(isHeader: true, headerText: "Непрочитанные"));
        listItems.addAll(unreadList.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
        if (otherList.isNotEmpty) {
          listItems.add(SidebarListItem(isHeader: true, headerText: "Остальные"));
          listItems.addAll(otherList.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
        }
      } else {
        listItems.addAll(otherList.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
      }
    } else {
      // Filter clients that have callback set (even in the future)
      final callbackClients = clients
          .where((item) => item.contact?.callbackTimeMs != null)
          .toList();

      // Sort chronologically by callback time
      callbackClients.sort((a, b) {
        return a.contact!.callbackTimeMs!.compareTo(b.contact!.callbackTimeMs!);
      });

      final tomorrowEnd = todayEnd.add(const Duration(days: 1));

      final overdue = <SidebarClientItem>[];
      final today = <SidebarClientItem>[];
      final tomorrow = <SidebarClientItem>[];
      final futureGroups = <String, List<SidebarClientItem>>{};

      const monthsRu = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"
      ];

      String formatDateKey(DateTime dt) {
        return "${dt.day} ${monthsRu[dt.month - 1]}";
      }

      for (var item in callbackClients) {
        final cbTime = item.contact!.callbackTime!;
        if (cbTime.isBefore(now)) {
          overdue.add(item);
        } else if (cbTime.isBefore(todayEnd)) {
          today.add(item);
        } else if (cbTime.isBefore(tomorrowEnd)) {
          tomorrow.add(item);
        } else {
          final key = formatDateKey(cbTime);
          if (!futureGroups.containsKey(key)) {
            futureGroups[key] = [];
          }
          futureGroups[key]!.add(item);
        }
      }

      if (overdue.isNotEmpty) {
        listItems.add(SidebarListItem(isHeader: true, headerText: "Пропущенные"));
        listItems.addAll(overdue.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
      }

      if (today.isNotEmpty) {
        listItems.add(SidebarListItem(isHeader: true, headerText: "Сегодня"));
        listItems.addAll(today.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
      }

      if (tomorrow.isNotEmpty) {
        listItems.add(SidebarListItem(isHeader: true, headerText: "Завтра"));
        listItems.addAll(tomorrow.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
      }

      final sortedKeys = futureGroups.keys.toList();
      for (var key in sortedKeys) {
        listItems.add(SidebarListItem(isHeader: true, headerText: key));
        listItems.addAll(futureGroups[key]!.map((c) => SidebarListItem(isHeader: false, clientItem: c)));
      }
    }

    final rawSearchQuery = ref.watch(searchQueryProvider).trim();
    final cleanPhoneQuery = rawSearchQuery.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final isPhoneQuery = RegExp(r'^\+?[0-9]{4,15}$').hasMatch(cleanPhoneQuery);

    if (isPhoneQuery && !clients.any((c) => RecipientImporter.isSamePhone(c.phone, rawSearchQuery))) {
      final normalizedQuery = RecipientImporter.normalizePhone(cleanPhoneQuery);
      final finalPhone = normalizedQuery.isNotEmpty ? normalizedQuery : cleanPhoneQuery;
      listItems.insert(
        0,
        SidebarListItem(
          isHeader: false,
          clientItem: SidebarClientItem(
            phone: finalPhone,
            contact: ContactDto(phone: finalPhone, name: "Открыть чат с номером", notes: "Нажмите для загрузки сообщений"),
          ),
        ),
      );
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
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      "КЛИЕНТЫ",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontFamily: 'Outfit',
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),

                    // Broadcast Campaign Button
                    Builder(builder: (context) {
                      final campaigns = ref.watch(campaignsProvider);
                      final runningCount = campaigns.where((c) => c.status == 'running').length;
                      final isBroadcastActive = ref.watch(activeViewModeProvider) == AppViewMode.broadcast;

                      return Tooltip(
                        message: isBroadcastActive ? "Закрыть рассылки" : "Массовые рассылки",
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              onPressed: () {
                                if (isBroadcastActive) {
                                  ref.read(activeViewModeProvider.notifier).set(AppViewMode.chats);
                                } else {
                                  ref.read(activeViewModeProvider.notifier).set(AppViewMode.broadcast);
                                  ref.read(selectedChatIdProvider.notifier).select(null);
                                }
                              },
                              icon: const Icon(Icons.campaign_rounded, size: 17),
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                                maximumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                                backgroundColor: isBroadcastActive
                                    ? AppColors.accent
                                    : AppColors.msgSent,
                                foregroundColor: Colors.white,
                                hoverColor: AppColors.accent.withValues(alpha: 0.8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            if (runningCount > 0)
                              Positioned(
                                right: -3,
                                top: -3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "$runningCount",
                                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(width: 6),

                    // Call Log Button
                    Builder(builder: (context) {
                      final isCallLogActive =
                          ref.watch(activeViewModeProvider) == AppViewMode.callLog;

                      return Tooltip(
                        message: isCallLogActive ? "Закрыть журнал звонков" : "Журнал звонков",
                        child: IconButton(
                          onPressed: () {
                            if (isCallLogActive) {
                              ref.read(activeViewModeProvider.notifier).set(AppViewMode.chats);
                            } else {
                              ref.read(activeViewModeProvider.notifier).set(AppViewMode.callLog);
                              ref.read(selectedChatIdProvider.notifier).select(null);
                              ref.read(callLogsProvider.notifier).load();
                            }
                          },
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 17),
                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            maximumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            backgroundColor: isCallLogActive
                                ? AppColors.accent
                                : AppColors.msgSent,
                            foregroundColor: Colors.white,
                            hoverColor: AppColors.accent.withValues(alpha: 0.8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 6),

                    // Contractor / OKVED Lookup Button (T-Bank)
                    Tooltip(
                      message: "Проверка контрагента (Т-Банк / ОКВЭД)",
                      child: IconButton(
                        onPressed: () => ContractorLookupDialog.show(context),
                        icon: const Icon(Icons.domain_verification_rounded, size: 17),
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          maximumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          backgroundColor: AppColors.msgSent,
                          hoverColor: AppColors.accent.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    
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
                          size: 17,
                        ),
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          maximumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          backgroundColor: AppColors.msgSent,
                          hoverColor: AppColors.accent.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Phone Volume Button
                    Consumer(
                      builder: (context, ref, _) {
                        final vol = ref.watch(deviceVolumeProvider);
                        final isMuted = vol.isMuted;
                        final percent = vol.maxRingVolume > 0
                            ? ((vol.ringVolume / vol.maxRingVolume) * 100).round()
                            : 0;

                        return Tooltip(
                          message: "Громкость телефона: $percent% (${vol.ringVolume}/${vol.maxRingVolume})\nНажмите для настройки",
                          child: IconButton(
                            onPressed: () => _showPhoneVolumeDialog(context, ref),
                            icon: Icon(
                              isMuted
                                  ? Icons.notifications_off_rounded
                                  : Icons.notifications_active_rounded,
                              color: isMuted
                                  ? AppColors.warning
                                  : AppColors.accentLight,
                              size: 17,
                            ),
                            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              maximumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              backgroundColor: AppColors.msgSent,
                              hoverColor: AppColors.accent.withValues(alpha: 0.15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),

                    // Headset / Bluetooth Status Icon (if connected)
                    Consumer(
                      builder: (context, ref, _) {
                        final vol = ref.watch(deviceVolumeProvider);
                        if (!vol.isBluetoothConnected && !vol.isWiredHeadsetConnected) {
                          return const SizedBox.shrink();
                        }
                        final isBt = vol.isBluetoothConnected;
                        final name = isBt
                            ? (vol.bluetoothDeviceName.isNotEmpty ? vol.bluetoothDeviceName : "Блютуз гарнитура")
                            : "Проводная гарнитура";

                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: "Подключено аудиоустройство:\n$name\nНажмите для настройки звука",
                            child: IconButton(
                              onPressed: () => _showPhoneVolumeDialog(context, ref),
                              icon: Icon(
                                isBt ? Icons.bluetooth_audio_rounded : Icons.headphones_rounded,
                                color: isBt ? const Color(0xFF60A5FA) : const Color(0xFF34D399),
                                size: 16,
                              ),
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                                maximumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                                backgroundColor: (isBt ? const Color(0xFF3B82F6) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                                hoverColor: (isBt ? const Color(0xFF3B82F6) : const Color(0xFF10B981)).withValues(alpha: 0.25),
                                side: BorderSide(
                                  color: (isBt ? const Color(0xFF3B82F6) : const Color(0xFF10B981)).withValues(alpha: 0.35),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // New Client Button
                    Tooltip(
                      message: "Добавить клиента",
                      child: IconButton(
                        onPressed: () => _showNewClientDialog(context, ref),
                        icon: const Icon(Icons.person_add_rounded, color: AppColors.textPrimary, size: 17),
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          maximumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          backgroundColor: AppColors.accent,
                          hoverColor: AppColors.accent.withValues(alpha: 0.8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                              "Все",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _selectedTab == SidebarTab.all
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Tab "Новые" (Сверху непрочитанные)
                      Expanded(
                        child: Tooltip(
                          message: "Сверху непрочитанные",
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedTab = SidebarTab.newest;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedTab == SidebarTab.newest
                                    ? AppColors.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _selectedTab == SidebarTab.newest
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
                                    "Новые",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _selectedTab == SidebarTab.newest
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (unreadTotal > 0) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _selectedTab == SidebarTab.newest
                                            ? Colors.white
                                            : AppColors.accent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "$unreadTotal",
                                        style: TextStyle(
                                          color: _selectedTab == SidebarTab.newest
                                              ? AppColors.accent
                                              : Colors.white,
                                          fontSize: 9.5,
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
                      ),
                      // Tab "Перезвонить"
                      Expanded(
                        child: Tooltip(
                          message: "Запланированные перезвоны",
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
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (callbackCount > 0) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                                          fontSize: 9.5,
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
            child: listItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
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
                    itemCount: listItems.length,
                    itemBuilder: (ctx, i) {
                      final listItem = listItems[i];
                      if (listItem.isHeader) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            listItem.headerText!.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.accentLight,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        );
                      }

                      final item = listItem.clientItem!;
                      final phone = item.phone;
                      final contact = item.contact ?? ContactDto(phone: phone, name: "", notes: "");
                      final lastMsg = item.lastMessage;
                      final isSelected = phone == selectedId;
                      final unreadCount = item.unreadCount;
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
                              ref.read(activeViewModeProvider.notifier).set(AppViewMode.chats);
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
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
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
                                      if (unreadCount > 0)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: AppColors.error,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(0xFF1E293B) // match background color approximately
                                                    : AppColors.background,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
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
                                            if (lastMsg != null)
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
                                                lastMsg != null ? lastMsg.body : "Нет переписки (только карточка)",
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
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}";
  }

  void _showNewClientDialog(BuildContext context, WidgetRef ref) {
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

              // Normalize with RecipientImporter (e.g. 7999... or 8999... -> +7999...)
              final normalized = RecipientImporter.normalizePhone(rawInput);
              final clean = normalized.isNotEmpty
                  ? normalized
                  : rawInput.replaceAll(RegExp(r'[\s\-()]+'), '');

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
              title: const Text("Добавить клиента"),
              content: TextField(
                controller: c,
                style: const TextStyle(color: AppColors.textPrimary),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s\-\(\)]')),
                  PhoneAutoPrefixFormatter(),
                ],
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
                  child: const Text("Открыть карточку"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPhoneVolumeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final vol = ref.watch(deviceVolumeProvider);
            final ringPercent = vol.maxRingVolume > 0
                ? ((vol.ringVolume / vol.maxRingVolume) * 100).round()
                : 0;

            return AlertDialog(
              backgroundColor: AppColors.cardBgSolid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.phone_android_rounded,
                      color: AppColors.accentLight,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Громкость телефона",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Active Audio Output Banner ---
                    Builder(
                      builder: (context) {
                        final isBt = vol.isBluetoothConnected;
                        final isWired = vol.isWiredHeadsetConnected;
                        final title = isBt
                            ? "Блютуз наушники подключены"
                            : (isWired ? "Проводная гарнитура подключена" : "Динамик телефона");
                        final subtitle = isBt
                            ? (vol.bluetoothDeviceName.isNotEmpty ? vol.bluetoothDeviceName : "Звонки направляются на гарнитуру")
                            : (isWired ? "Звонки направляются в гарнитуру" : "Гарнитура не подключена");

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isBt
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                                : (isWired ? const Color(0xFF10B981).withValues(alpha: 0.12) : AppColors.cardBgSolid),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isBt
                                  ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                                  : (isWired ? const Color(0xFF10B981).withValues(alpha: 0.3) : AppColors.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: isBt
                                      ? const Color(0xFF3B82F6).withValues(alpha: 0.2)
                                      : (isWired ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.white10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isBt
                                      ? Icons.bluetooth_audio_rounded
                                      : (isWired ? Icons.headphones_rounded : Icons.phone_android_rounded),
                                  size: 16,
                                  color: isBt
                                      ? const Color(0xFF60A5FA)
                                      : (isWired ? const Color(0xFF34D399) : AppColors.textSecondary),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: isBt
                                            ? const Color(0xFF93C5FD)
                                            : (isWired ? const Color(0xFF6EE7B7) : AppColors.textPrimary),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // --- Ringtone Volume ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.notifications_rounded, size: 16, color: AppColors.accentLight),
                            SizedBox(width: 8),
                            Text(
                              "Громкость звонка (вызов)",
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "$ringPercent% (${vol.ringVolume}/${vol.maxRingVolume})",
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            ref.read(deviceVolumeProvider.notifier).ringVolumeDown();
                            SfxService.playSent();
                          },
                          icon: const Icon(Icons.remove_rounded, color: AppColors.textPrimary),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.msgSent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.accent,
                              inactiveTrackColor: Colors.white10,
                              thumbColor: AppColors.accentLight,
                              overlayColor: AppColors.accent.withValues(alpha: 0.2),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: vol.ringVolume.toDouble().clamp(0.0, vol.maxRingVolume.toDouble()),
                              min: 0,
                              max: vol.maxRingVolume > 0 ? vol.maxRingVolume.toDouble() : 15.0,
                              divisions: vol.maxRingVolume > 0 ? vol.maxRingVolume : 15,
                              onChanged: (newVal) {
                                ref.read(deviceVolumeProvider.notifier).setRingVolume(newVal.round());
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            ref.read(deviceVolumeProvider.notifier).ringVolumeUp();
                            SfxService.playSent();
                          },
                          icon: const Icon(Icons.add_rounded, color: AppColors.textPrimary),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.msgSent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick Mute / Max Ringtone Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ref.read(deviceVolumeProvider.notifier).setRingVolume(0);
                              SfxService.playSent();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            icon: const Icon(Icons.notifications_off_rounded, size: 15),
                            label: const Text("Без звука", style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ref.read(deviceVolumeProvider.notifier).setRingVolume(vol.maxRingVolume);
                              SfxService.playSent();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.success,
                              side: BorderSide(color: AppColors.success.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            icon: const Icon(Icons.volume_up_rounded, size: 15),
                            label: const Text("Максимум", style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 16),

                    // --- In-Call Voice Volume ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.phone_in_talk_rounded, size: 16, color: Color(0xFF38BDF8)),
                            SizedBox(width: 8),
                            Text(
                              "Громкость разговора (в трубке)",
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "${vol.callVolume}/${vol.maxCallVolume}",
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            ref.read(deviceVolumeProvider.notifier).callVolumeDown();
                            SfxService.playSent();
                          },
                          icon: const Icon(Icons.remove_rounded, color: AppColors.textPrimary),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.msgSent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: vol.maxCallVolume > 0
                                  ? (vol.callVolume / vol.maxCallVolume).clamp(0.0, 1.0)
                                  : 0.5,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation(Color(0xFF38BDF8)),
                              minHeight: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () {
                            ref.read(deviceVolumeProvider.notifier).callVolumeUp();
                            SfxService.playSent();
                          },
                          icon: const Icon(Icons.add_rounded, color: AppColors.textPrimary),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.msgSent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Готово", style: TextStyle(color: AppColors.accentLight)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}