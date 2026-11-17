import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../../utils/recipient_importer.dart';
import '../../utils/copy_helper.dart';
import '../widgets/chat_window.dart';
import '../widgets/inline_date_time_picker.dart';
import '../../../shared/shared_models.dart';
import '../../../shared/theme.dart';
import 'contractor/contractor_lookup_dialog.dart';

class ClientCardView extends ConsumerStatefulWidget {
  final String phone;

  const ClientCardView({super.key, required this.phone});

  @override
  ConsumerState<ClientCardView> createState() => _ClientCardViewState();
}

class _ClientCardViewState extends ConsumerState<ClientCardView> {
  late TextEditingController _nameCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _commentCtrl;
  late FocusNode _nameFocus;
  late FocusNode _notesFocus;
  String _selectedStatus = "успех";
  String _callHistoryFilter = "all"; // "all", "device", "crm"
  bool _isChatExpanded = false;
  bool _isClientCardHidden = false;
  double _crmCardWidth = 460.0;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _commentCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _notesFocus = FocusNode();

    // Check if client has active threads to expand chat by default
    final threads = ref.read(threadsProvider);
    _isChatExpanded = _hasMessagesForPhone(threads, widget.phone);

    // Initial load of system call logs
    Future.microtask(() {
      ref.read(callLogsProvider.notifier).load();
    });
  }

  bool _hasMessagesForPhone(Map<String, List<SmsMessageDto>> threads, String phone) {
    for (var entry in threads.entries) {
      if (RecipientImporter.isSamePhone(entry.key, phone)) {
        return entry.value.isNotEmpty;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _commentCtrl.dispose();
    _nameFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClientCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phone != widget.phone) {
      _commentCtrl.clear();
      _selectedStatus = "успех";
      FocusManager.instance.primaryFocus?.unfocus();
      _nameCtrl.clear();
      _notesCtrl.clear();

      final threads = ref.read(threadsProvider);
      _isChatExpanded = _hasMessagesForPhone(threads, widget.phone);

      Future.microtask(() {
        ref.read(callLogsProvider.notifier).load();
      });
    }
  }

  void _syncInputs(ContactDto contact) {
    if (!_nameFocus.hasFocus && _nameCtrl.text != contact.name) {
      _nameCtrl.text = contact.name;
    }
    if (!_notesFocus.hasFocus && _notesCtrl.text != contact.notes) {
      _notesCtrl.text = contact.notes;
    }
  }

  void _copyPhone(String phone) {
    copyToClipboard(phone);
    SfxService.playSent();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              "Номер $phone скопирован в буфер",
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        backgroundColor: AppColors.cardBgSolid,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final threads = ref.watch(threadsProvider);
    final unreadCounts = ref.watch(unreadCountsProvider);
    
    final contact = contacts.firstWhere(
      (c) => RecipientImporter.isSamePhone(c.phone, widget.phone),
      orElse: () => ContactDto(phone: widget.phone, name: "", notes: ""),
    );

    _syncInputs(contact);
    
    int unreadForThisClient = unreadCounts[widget.phone] ?? 0;
    if (unreadForThisClient == 0) {
      for (var entry in unreadCounts.entries) {
        if (RecipientImporter.isSamePhone(entry.key, widget.phone)) {
          unreadForThisClient = entry.value;
          break;
        }
      }
    }
    final hasChatMessages = _hasMessagesForPhone(threads, widget.phone);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // If the CRM client card is hidden completely, expand chat to 100%
          if (_isClientCardHidden) {
            return ChatWindow(
              phone: widget.phone,
              hideHeader: false,
              onShowClientCard: () => setState(() => _isClientCardHidden = false),
            );
          }

          final isChatExpanded = _isChatExpanded;
          
          if (!isChatExpanded) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(contact, unreadForThisClient),
                    const SizedBox(height: 28),
                    _buildCrmContent(contact, false),
                    if (!hasChatMessages)
                      _buildNoChatBanner(),
                  ],
                ),
              ),
            );
          }

          // Both Client Card & Chat are active. Calculate resizable width bounds
          final maxCrmWidth = (constraints.maxWidth - 320.0).clamp(280.0, constraints.maxWidth);
          final effectiveCrmWidth = _crmCardWidth.clamp(280.0, maxCrmWidth);
          final useSingleColumn = effectiveCrmWidth < 680;

          return Row(
            children: [
              // Client CRM Card Panel (Resizable width)
              SizedBox(
                width: effectiveCrmWidth,
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(contact, unreadForThisClient),
                        const SizedBox(height: 28),
                        _buildCrmContent(contact, useSingleColumn),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Vertical Draggable Splitter Handle
              GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _crmCardWidth = (_crmCardWidth + details.delta.dx).clamp(280.0, constraints.maxWidth - 320.0);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: 12,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Chat Window Panel (Takes remaining space)
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: AppColors.border, width: 1)),
                  ),
                  child: ChatWindow(
                    phone: widget.phone,
                    hideHeader: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCrmContent(ContactDto contact, bool useSingleColumn) {
    if (!useSingleColumn) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: _buildCrmFormCard(contact),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildCallLogAndSchedulerCard(contact),
                const SizedBox(height: 24),
                _buildCallHistoryCard(contact),
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCrmFormCard(contact),
          const SizedBox(height: 24),
          _buildCallLogAndSchedulerCard(contact),
          const SizedBox(height: 24),
          _buildCallHistoryCard(contact),
        ],
      );
    }
  }

  Widget _buildNoChatBanner() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: InkWell(
        onTap: () => setState(() => _isChatExpanded = true),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, color: AppColors.accentLight),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "У этого клиента ещё нет SMS-переписки",
                      style: TextStyle(
                        color: AppColors.textPrimary, 
                        fontWeight: FontWeight.bold, 
                        fontSize: 14,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Нажмите здесь, чтобы открыть чат и отправить первое сообщение.",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _openContractorLookup(ContactDto contact) {
    String query = contact.name.trim();
    if (query == "Новый контакт" || query.isEmpty) {
      final innMatch = RegExp(r'\b\d{10}\b|\b\d{12}\b').firstMatch(_notesCtrl.text);
      if (innMatch != null) {
        query = innMatch.group(0)!;
      } else {
        query = _notesCtrl.text.trim();
      }
    }

    ContractorLookupDialog.show(
      context,
      initialQuery: query.isNotEmpty ? query : null,
      onApplyToContact: (contractor) async {
        setState(() {
          if (_nameCtrl.text.isEmpty || _nameCtrl.text == "Новый контакт") {
            _nameCtrl.text = contractor.name;
          }
          final formatted = contractor.toFormattedRequisites();
          if (!_notesCtrl.text.contains(contractor.inn)) {
            _notesCtrl.text = _notesCtrl.text.isEmpty
                ? formatted
                : "${_notesCtrl.text}\n\n$formatted".trim();
          }
        });
        final updated = ContactDto(
          phone: contact.phone,
          name: _nameCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          callbackTimeMs: contact.callbackTimeMs,
          callHistory: contact.callHistory,
        );
        await ref.read(contactsProvider.notifier).save(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Реквизиты ${contractor.name} сохранены"),
              backgroundColor: AppColors.accent,
            ),
          );
          SfxService.playSuccess();
        }
      },
    );
  }

  Widget _buildHeader(ContactDto contact, int unreadCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Avatar + Name & Phone (Takes full width, prevents vertical squishing)
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              child: Text(
                contact.name.isNotEmpty
                    ? contact.name[0].toUpperCase()
                    : "?",
                style: const TextStyle(
                  color: AppColors.accentLight,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name.isNotEmpty ? contact.name : "Новый контакт",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            fontFamily: 'Outfit',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (contact.notes.contains('Селлер') || contact.notes.contains('47.91')) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 13, color: Colors.purpleAccent),
                              SizedBox(width: 4),
                              Text(
                                'Селлер',
                                style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _copyPhone(contact.phone),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            contact.phone,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: "Скопировать номер",
                            child: Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: AppColors.textSecondary.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Row 2: Action Buttons (Grouped neatly below contact details)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // PC Phone Call Button
            Builder(
              builder: (context) {
                final activeCall = ref.watch(activeCallProvider);
                final isCurrentCall = activeCall.isInCall &&
                    activeCall.phoneNumber != null &&
                    RecipientImporter.isSamePhone(activeCall.phoneNumber!, contact.phone);

                return Tooltip(
                  message: isCurrentCall ? "Сбросить звонок" : "Позвонить с телефона",
                  child: IconButton(
                    icon: Icon(
                      isCurrentCall ? Icons.call_end_rounded : Icons.phone_in_talk_rounded,
                      color: isCurrentCall ? AppColors.error : Colors.greenAccent,
                      size: 18,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: (isCurrentCall ? AppColors.error : Colors.greenAccent).withValues(alpha: 0.15),
                      hoverColor: (isCurrentCall ? AppColors.error : Colors.greenAccent).withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(10),
                    ),
                    onPressed: () async {
                      if (isCurrentCall) {
                        await ref.read(activeCallProvider.notifier).hangup();
                        return;
                      }
                      final sims = ref.read(simsProvider);
                      final subId = ref.read(selectedSimProvider) ?? (sims.isNotEmpty ? sims.first.subscriptionId : -1);
                      final api = ref.read(apiClientProvider);
                      if (api != null) {
                        try {
                          ref.read(activeCallProvider.notifier).startCall(contact.phone, contactName: contact.name);
                          await api.makeCall(contact.phone, subId);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Команда на вызов отправлена на телефон")),
                          );
                          SfxService.playSent();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Ошибка вызова: $e"), backgroundColor: AppColors.error),
                          );
                        }
                      }
                    },
                  ),
                );
              },
            ),

            // Phone Ring Volume Quick Controller
            Consumer(
              builder: (context, ref, _) {
                final vol = ref.watch(deviceVolumeProvider);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.cardBgSolid,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: "Убавить громкость звонка на телефоне",
                        child: IconButton(
                          icon: const Icon(Icons.volume_down_rounded, size: 16, color: AppColors.textSecondary),
                          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            ref.read(deviceVolumeProvider.notifier).ringVolumeDown();
                            SfxService.playSent();
                          },
                        ),
                      ),
                      Tooltip(
                        message: "Громкость звонка телефона: ${vol.ringVolume}/${vol.maxRingVolume}",
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                vol.isMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                                size: 14,
                                color: vol.isMuted ? AppColors.warning : AppColors.accentLight,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${vol.ringVolume}",
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Tooltip(
                        message: "Прибавить громкость звонка на телефоне",
                        child: IconButton(
                          icon: const Icon(Icons.volume_up_rounded, size: 16, color: AppColors.textSecondary),
                          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            ref.read(deviceVolumeProvider.notifier).ringVolumeUp();
                            SfxService.playSent();
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Headset / Bluetooth Audio Indicator
            Consumer(
              builder: (context, ref, _) {
                final vol = ref.watch(deviceVolumeProvider);
                if (!vol.isBluetoothConnected && !vol.isWiredHeadsetConnected) {
                  return const SizedBox.shrink();
                }
                final isBt = vol.isBluetoothConnected;
                final name = isBt
                    ? (vol.bluetoothDeviceName.isNotEmpty ? vol.bluetoothDeviceName : "Блютуз")
                    : "Гарнитура";

                return Tooltip(
                  message: isBt
                      ? "Подключены блютуз наушники:\n$name\nЗвонки идут через гарнитуру"
                      : "Подключена проводная гарнитура",
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isBt
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                          : const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isBt
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
                            : const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isBt ? Icons.bluetooth_audio_rounded : Icons.headphones_rounded,
                          size: 15,
                          color: isBt ? const Color(0xFF60A5FA) : const Color(0xFF34D399),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          name,
                          style: TextStyle(
                            color: isBt ? const Color(0xFF93C5FD) : const Color(0xFF6EE7B7),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Toggle Chat Button
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isChatExpanded = !_isChatExpanded;
                });
              },
              icon: Icon(
                _isChatExpanded ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 16,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_isChatExpanded ? "Скрыть чат" : "SMS Чат"),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "$unreadCount",
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isChatExpanded ? AppColors.accent : AppColors.cardBgSolid,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                elevation: 0,
                side: BorderSide(
                  color: _isChatExpanded ? Colors.transparent : AppColors.border,
                ),
              ),
            ),

            // T-Bank Contractor & OKVED Lookup Button
            Tooltip(
              message: "Проверить реквизиты и виды деятельности (ОКВЭД) в Т-Банке",
              child: OutlinedButton.icon(
                onPressed: () => _openContractorLookup(contact),
                icon: const Icon(Icons.domain_verification_rounded, size: 16, color: AppColors.accentLight),
                label: const Text("Проверить в Т-Банке"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  backgroundColor: AppColors.cardBgSolid,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),

            // Hide CRM Card Button
            if (_isChatExpanded)
              Tooltip(
                message: "Скрыть карточку клиента",
                child: IconButton(
                  icon: const Icon(Icons.dock_rounded, color: AppColors.textSecondary, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.cardBgSolid,
                    hoverColor: AppColors.accent.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.all(10),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: () => setState(() => _isClientCardHidden = true),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCrmFormCard(ContactDto contact) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Карточка CRM",
            style: TextStyle(
              color: AppColors.accentLight,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          // Phone number tile with copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Номер телефона",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        contact.phone,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: "Скопировать номер",
                  child: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    color: AppColors.accentLight,
                    onPressed: () => _copyPhone(contact.phone),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            focusNode: _nameFocus,
            spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: "Имя / Подпись",
              labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              filled: true,
              fillColor: Colors.black12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Заметки и реквизиты",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: () => _openContractorLookup(contact),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    children: [
                      Icon(Icons.domain_verification_rounded, size: 14, color: AppColors.accentLight),
                      SizedBox(width: 4),
                      Text(
                        "Найти в Т-Банке (ОКВЭД)",
                        style: TextStyle(
                          color: AppColors.accentLight,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            focusNode: _notesFocus,
            spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
            maxLines: 4,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Заметки, ИНН, реквизиты контрагента...",
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              filled: true,
              fillColor: Colors.black12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final updated = ContactDto(
                  phone: contact.phone,
                  name: _nameCtrl.text.trim(),
                  notes: _notesCtrl.text.trim(),
                  callbackTimeMs: contact.callbackTimeMs,
                  callHistory: contact.callHistory,
                );
                await ref.read(contactsProvider.notifier).save(updated);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Данные сохранены")),
                  );
                  SfxService.playSuccess();
                }
              },
              child: const Text("Сохранить инфо", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallLogAndSchedulerCard(ContactDto contact) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Регистрация звонка",
            style: TextStyle(
              color: AppColors.accentLight,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
                  dropdownColor: AppColors.cardBgSolid,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: "Статус",
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: "Дозвон", child: Text("Дозвон")),
                    DropdownMenuItem(value: "ндз", child: Text("ндз")),
                    DropdownMenuItem(value: "перезвон", child: Text("перезвон")),
                    DropdownMenuItem(value: "успех", child: Text("успех")),
                    DropdownMenuItem(value: "пропущен", child: Text("пропущен")),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedStatus = val;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _commentCtrl,
                  spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: "Комментарий к звонку",
                    labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    hintText: "О чем поговорили...",
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final List<CallRecordDto> updatedHistory = List.from(contact.callHistory);
                final commentText = _commentCtrl.text.trim();
                
                updatedHistory.add(CallRecordDto(
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  comment: commentText,
                  status: _selectedStatus,
                ));

                final newContact = ContactDto(
                  phone: contact.phone,
                  name: _nameCtrl.text.trim(),
                  notes: _notesCtrl.text.trim(),
                  callbackTimeMs: contact.callbackTimeMs,
                  callHistory: updatedHistory,
                );
                await ref.read(contactsProvider.notifier).save(newContact);
                _commentCtrl.clear();
                setState(() {
                  _selectedStatus = "успех";
                });
                SfxService.playSuccess();
              },
              child: const Text("Добавить звонок в историю", style: TextStyle(color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 20),
          _buildSchedulerSection(contact),
        ],
      ),
    );
  }

  Widget _buildSchedulerSection(ContactDto contact) {
    final hasCallback = contact.callbackTimeMs != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Запланировать перезвон",
          style: TextStyle(
            color: AppColors.accentLight,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        const SizedBox(height: 12),
        if (hasCallback)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_alarm_rounded, color: AppColors.accentLight, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Запланирован на: ${_formatDateTimeString(contact.callbackTime!)}",
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: AppColors.accentLight, size: 16),
                  tooltip: "Изменить время",
                  onPressed: () => _showCallbackDialog(contact),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 16),
                  tooltip: "Отменить перезвон",
                  onPressed: () async {
                    await ref.read(contactsProvider.notifier).clearCallback(contact);
                    SfxService.playSuccess();
                  },
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                foregroundColor: AppColors.accentLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: const Text("Запланировать перезвон", style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _showCallbackDialog(contact),
            ),
          ),
      ],
    );
  }

  Future<void> _showCallbackDialog(ContactDto contact) async {
    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => CallbackScheduleDialog(initialDateTime: contact.callbackTime),
    );
    if (result != null) {
      final updated = ContactDto(
        phone: contact.phone,
        name: _nameCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        callbackTimeMs: result.millisecondsSinceEpoch,
        callHistory: contact.callHistory,
      );
      await ref.read(contactsProvider.notifier).save(updated);
      SfxService.playSuccess();
    }
  }

  String _formatDateTimeString(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$d.$m.$y в $h:$min";
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return "0 сек";
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes == 0) return "$seconds сек";
    return "$minutesм ${seconds.toString().padLeft(2, '0')}с";
  }

  String _formatCallDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "Сегодня в $timeStr";
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return "Вчера в $timeStr";
    }
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} $timeStr";
  }

  Widget _buildCallHistoryCard(ContactDto contact) {
    final allCallLogs = ref.watch(callLogsProvider);
    final deviceCalls = allCallLogs
        .where((c) => RecipientImporter.isSamePhone(c.number, contact.phone))
        .toList();

    final crmRecords = contact.callHistory;
    final totalCount = deviceCalls.length + crmRecords.length;

    // Filter items according to active tab
    final List<_TimelineCallItem> items = [];
    if (_callHistoryFilter == "all" || _callHistoryFilter == "device") {
      for (var call in deviceCalls) {
        items.add(_TimelineCallItem.device(call));
      }
    }
    if (_callHistoryFilter == "all" || _callHistoryFilter == "crm") {
      for (var record in crmRecords) {
        items.add(_TimelineCallItem.crm(record));
      }
    }

    // Sort chronologically descending (newest first)
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    "История звонков",
                    style: TextStyle(
                      color: AppColors.accentLight,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$totalCount",
                      style: const TextStyle(
                        color: AppColors.accentLight,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Tooltip(
                message: "Обновить журнал звонков",
                child: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    await ref.read(callLogsProvider.notifier).load();
                    SfxService.playSent();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filter selector tabs
          Row(
            children: [
              _buildFilterChip("Все ($totalCount)", "all"),
              const SizedBox(width: 6),
              _buildFilterChip("Телефон (${deviceCalls.length})", "device"),
              const SizedBox(width: 6),
              _buildFilterChip("CRM (${crmRecords.length})", "crm"),
            ],
          ),
          const SizedBox(height: 14),

          if (totalCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.phone_missed_rounded,
                    size: 32,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Звонки пока не зафиксированы",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(callLogsProvider.notifier).load();
                      SfxService.playSent();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text("Загрузить журнал звонков", style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: items.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.isDeviceCall) {
                    return _buildDeviceCallRow(item.deviceCall!);
                  } else {
                    return _buildCrmRecordRow(item.crmRecord!);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _callHistoryFilter == value;
    return InkWell(
      onTap: () => setState(() => _callHistoryFilter = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceCallRow(CallLogEntryDto call) {
    final isIncoming = call.direction.toLowerCase().contains('in');
    final isMissed = call.status == 'пропущен' ||
        call.status == 'сброшен' ||
        (call.durationSeconds == 0 && isIncoming);

    IconData icon;
    Color color;
    String statusTitle;

    if (isMissed) {
      icon = Icons.call_missed_rounded;
      color = AppColors.error;
      statusTitle = "Пропущенный вызов";
    } else if (isIncoming) {
      icon = Icons.call_received_rounded;
      color = const Color(0xFF38BDF8);
      statusTitle = "Входящий звонок";
    } else {
      icon = Icons.call_made_rounded;
      color = const Color(0xFF10B981);
      statusTitle = call.durationSeconds > 0 ? "Исходящий звонок" : "Исходящий (нет ответа)";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      statusTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "Телефон",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCallDate(call.date),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          if (call.durationSeconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Text(
                _formatDuration(call.durationSeconds),
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            )
          else
            Text(
              isMissed ? "без ответа" : "0 сек",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildCrmRecordRow(CallRecordDto record) {
    Color statusColor;
    switch (record.status) {
      case 'успех':
        statusColor = Colors.greenAccent;
        break;
      case 'перезвон':
        statusColor = Colors.orangeAccent;
        break;
      case 'ндз':
        statusColor = Colors.redAccent;
        break;
      case 'пропущен':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = Colors.blueAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      record.status,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "Заметка CRM",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
                    ),
                  ),
                ],
              ),
              Text(
                _formatCallDate(record.timestamp),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          if (record.comment.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              record.comment,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineCallItem {
  final int timestamp;
  final bool isDeviceCall;
  final CallLogEntryDto? deviceCall;
  final CallRecordDto? crmRecord;

  _TimelineCallItem.device(CallLogEntryDto call)
      : timestamp = call.date,
        isDeviceCall = true,
        deviceCall = call,
        crmRecord = null;

  _TimelineCallItem.crm(CallRecordDto record)
      : timestamp = record.timestamp,
        isDeviceCall = false,
        deviceCall = null,
        crmRecord = record;
}

