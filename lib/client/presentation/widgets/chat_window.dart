import 'package:android_host/shared/shared_models.dart';
import 'package:android_host/client/utils/copy_helper.dart';
import 'package:android_host/client/utils/selection_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers.dart';
import '../../../shared/theme.dart';
import '../../../shared/storage_helper.dart' as storage;
import 'message_bubble.dart';
import 'inline_date_time_picker.dart';
import '../../utils/recipient_importer.dart';

class HighlightingTextController extends TextEditingController {
  List<ValidationIssue> issues = [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (issues.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final List<TextSpan> spans = [];
    int start = 0;

    // Сортируем ошибки по позиции
    final sortedIssues = List<ValidationIssue>.from(issues)
      ..sort((a, b) => a.start.compareTo(b.start));

    for (var issue in sortedIssues) {
      if (issue.start >= text.length) break;
      final end = issue.end.clamp(0, text.length);
      if (end <= start) continue;

      final issueStart = issue.start < start ? start : issue.start;
      // Текст до ошибки
      if (issueStart > start) {
        spans.add(TextSpan(text: text.substring(start, issueStart)));
      }

      // Текст с ошибкой
      if (end > issueStart) {
        final isSpam = issue.isSpamTrigger;
        spans.add(
          TextSpan(
            text: text.substring(issueStart, end),
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.wavy,
              decorationColor: isSpam
                  ? Colors.deepOrangeAccent
                  : AppColors.warning,
              backgroundColor: isSpam
                  ? const Color(0x33FF9800)
                  : const Color(0x22818CF8), // Glowing amber vs indigo-violet
            ),
          ),
        );
      }
      start = end;
    }
    // Оставшийся текст
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(children: spans, style: style);
  }
}

class ChatWindow extends ConsumerStatefulWidget {
  final String phone;
  final bool hideHeader;
  final VoidCallback? onShowClientCard;
  const ChatWindow({
    required this.phone,
    this.hideHeader = false,
    this.onShowClientCard,
    super.key,
  });

  @override
  ConsumerState<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends ConsumerState<ChatWindow> {
  final _controller = HighlightingTextController();
  final _scrollController = ScrollController();
  String _currentValidationText = "";
  bool _isTemplateOpen = false;
  bool _isValidationExpanded = false;
  ChatMessagesNotifier? _currentNotifier;

  @override
  void initState() {
    super.initState();
    _initSim();
    _scrollController.addListener(_onScroll);
    _controller.text = storage.getDraft(widget.phone) ?? "";
    _currentValidationText = _controller.text;
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _currentNotifier = ref.read(chatMessagesProvider(widget.phone));
        _currentNotifier?.addListener(_onMessageAdded);
      }
    });
  }

  @override
  void didUpdateWidget(ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phone != widget.phone) {
      // Save draft for old phone
      storage.setDraft(oldWidget.phone, _controller.text);

      // Сбрасываем временные игнорирования для нового чата
      Future.microtask(() {
        if (mounted) {
          ref.read(ignoredIssuesProvider.notifier).resetNow();
        }
      });

      // Update provider listeners
      _currentNotifier?.removeListener(_onMessageAdded);
      _currentNotifier = ref.read(chatMessagesProvider(widget.phone));
      _currentNotifier?.addListener(_onMessageAdded);

      // Reload draft for new phone
      _controller.removeListener(_onControllerChanged);
      _controller.text = storage.getDraft(widget.phone) ?? "";
      _currentValidationText = _controller.text;
      _controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _controller.removeListener(_onControllerChanged);
    _currentNotifier?.removeListener(_onMessageAdded);
    _currentNotifier = null;
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {
      _currentValidationText = _controller.text;
    });
    storage.setDraft(widget.phone, _controller.text);
  }

  void _onMessageAdded() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - 200) {
      _scrollToBottom();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels < 100) {
      ref.read(chatMessagesProvider(widget.phone)).loadMore();
    }
  }

  void _initSim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sims = ref.read(simsProvider);
      final currentSelected = ref.read(selectedSimProvider);
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

  void _applyAllFixes() {
    final localIssues = ref.read(textValidationProvider(_controller.text));
    final allIssues = localIssues;

    var sortedIssues = List<ValidationIssue>.from(allIssues)
      ..sort((a, b) => b.start.compareTo(a.start));

    var currentText = _controller.text;
    for (var issue in sortedIssues) {
      if (issue.suggestion != null) {
        if (issue.start >= 0 && issue.end <= currentText.length) {
          currentText = currentText.replaceRange(
            issue.start,
            issue.end,
            issue.suggestion!,
          );
        }
      }
    }
    _controller.text = currentText;
    _controller.issues = [];
    SfxService.playSuccess();
  }

  bool _isSending = false;

  void _send() async {
    if (_isSending) return;
    final txt = _controller.text.trim();
    final selectedSimId = ref.read(selectedSimProvider);
    final api = ref.read(apiClientProvider);
    if (txt.isEmpty || selectedSimId == null || api == null) return;
    setState(() => _isSending = true);

    try {
      await api.sendSms(widget.phone, txt, selectedSimId);
      if (!mounted) return;
      _controller.clear();
      _controller.issues = [];
      storage.setDraft(widget.phone, "");
      ref.read(ignoredIssuesProvider.notifier).resetNow();
      SfxService.playSent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Ошибка отправки: $e",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _isSameDay(int ms1, int ms2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ms1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ms2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  String _formatDateLabel(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return "Сегодня";
    }
    return "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch<ChatMessagesNotifier>(
      chatMessagesProvider(widget.phone),
    );
    final sims = ref.watch(simsProvider);
    final contacts = ref.watch(contactsProvider);
    final contact = contacts.firstWhere(
      (c) => c.phone == widget.phone,
      orElse: () => ContactDto(phone: widget.phone, name: "", notes: ""),
    );

    final allIssues = ref.watch(textValidationProvider(_currentValidationText));

    _controller.issues = allIssues;

    // Determine deterministic gradient for user avatar in header
    final startColor = Color(
      (widget.phone.hashCode * 0xFF7A) | 0xFF000000,
    ).withValues(alpha: 0.85);
    final endColor = Color(
      (widget.phone.hashCode * 0x33B1) | 0xFF000000,
    ).withValues(alpha: 0.85);

    return ListenableBuilder(
      listenable: chatState,
      builder: (context, _) {
        final messages = chatState.state;
        final int? currentThreadId = messages.isNotEmpty
            ? messages.first.threadId
            : null;

        return Container(
          color: AppColors.background,
          child: Stack(
            children: [
              // Chat Layout
              Column(
                children: [
                  if (!widget.hideHeader)
                    _buildHeader(
                      currentThreadId,
                      startColor,
                      endColor,
                      contact,
                    ),
                  _buildMessageList(messages, chatState.hasMore, sims),
                  _buildInputArea(allIssues),
                ],
              ),

              // Slide-out Template Drawer Overlay
              if (_isTemplateOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _isTemplateOpen = false),
                    child: Container(color: Colors.black45),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                right: _isTemplateOpen ? 0 : -350,
                top: 0,
                bottom: 0,
                child: _buildTemplateDrawer(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValidationBar(List<ValidationIssue> issues) {
    final spamIssues = issues.where((i) => i.isSpamTrigger).toList();
    final normalIssues = issues.where((i) => !i.isSpamTrigger).toList();
    final hasSpam = spamIssues.isNotEmpty;

    final barBgColor = hasSpam
        ? const Color(0x29FF9800) // Translucent amber/orange
        : AppColors.msgSent.withValues(alpha: 0.12); // Translucent slate/indigo

    final borderColor = hasSpam
        ? const Color(0xFFFF9800).withValues(alpha: 0.3)
        : AppColors.border;

    return Container(
      decoration: BoxDecoration(
        color: barBgColor,
        border: Border(
          top: const BorderSide(color: AppColors.border),
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Шапка панели проверки
          InkWell(
            onTap: () =>
                setState(() => _isValidationExpanded = !_isValidationExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    hasSpam ? Icons.gavel_rounded : Icons.spellcheck_rounded,
                    size: 18,
                    color: hasSpam
                        ? const Color(0xFFFF9800)
                        : AppColors.accentLight,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasSpam
                          ? "Анализ текста: ${spamIssues.length} рисков блокировки, ${normalIssues.length} опечаток"
                          : "Анализ текста: ${issues.length} замечаний найдено",
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _isValidationExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  if (normalIssues.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _applyAllFixes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.2,
                        ),
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        "Исправить всё",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Развернутый список плашек в виде компактного ряда (Wrap)
          if (_isValidationExpanded && issues.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: 12,
                  top: 4,
                ),
                child: Wrap(
                  spacing: 8.0, // Горизонтальное расстояние между плашками
                  runSpacing: 8.0, // Вертикальное расстояние при переносе строк
                  alignment: WrapAlignment.start,
                  children: List.generate(issues.length, (index) {
                    final issue = issues[index];
                    final isSpam = issue.isSpamTrigger;

                    final word =
                        (issue.start >= 0 &&
                            issue.end <= _controller.text.length)
                        ? _controller.text.substring(issue.start, issue.end)
                        : "";

                    final itemBgColor = isSpam
                        ? const Color(0x1FFF5722)
                        : AppColors.msgReceived.withValues(alpha: 0.4);

                    final itemBorderColor = isSpam
                        ? const Color(0xFFFF5722).withValues(alpha: 0.3)
                        : AppColors.border;

                    return Container(
                      constraints: const BoxConstraints(
                        maxWidth: 320,
                      ), // Ограничиваем максимальную ширину отдельной ошибки
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: itemBgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: itemBorderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize
                            .min, // Компактный размер по содержимому
                        children: [
                          Icon(
                            isSpam
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline_rounded,
                            size: 14,
                            color: isSpam
                                ? Colors.deepOrangeAccent
                                : AppColors.accentLight,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  issue.message,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (issue.suggestion != null) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        "Заменить: ",
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        "\"${issue.suggestion}\"",
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          final currentText = _controller.text;
                                          if (issue.start >= 0 &&
                                              issue.end <= currentText.length) {
                                            _controller.text = currentText
                                                .replaceRange(
                                                  issue.start,
                                                  issue.end,
                                                  issue.suggestion!,
                                                );
                                            _controller.selection =
                                                TextSelection.fromPosition(
                                                  TextPosition(
                                                    offset:
                                                        _controller.text.length,
                                                  ),
                                                );
                                            SfxService.playSuccess();
                                          }
                                        },
                                        child: const Text(
                                          "Применить",
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Меню действий (Игнорировать)
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            style: const ButtonStyle(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            color: AppColors.cardBgSolid,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            onSelected: (action) {
                              final signature = "${issue.message}:$word";
                              if (action == 'ignore_now') {
                                ref
                                    .read(ignoredIssuesProvider.notifier)
                                    .ignoreNow(signature);
                              } else if (action == 'ignore_always') {
                                // Игнорируем слово целиком, если оно определено, иначе тип ошибки
                                final target = word.isNotEmpty
                                    ? word
                                    : issue.message;
                                ref
                                    .read(ignoredIssuesProvider.notifier)
                                    .ignoreAlways(target);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'ignore_now',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.visibility_off_outlined,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Игнорировать сейчас",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'ignore_always',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.block_outlined,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Игнорировать всегда",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputTopBar(
    List<SimCardDto> sims,
    int? selectedSimId,
    SmsBillingInfo billing,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sims.isNotEmpty) _buildPhysicalSimSlot(sims, selectedSimId),
              if (sims.isNotEmpty) const SizedBox(width: 8),

              // Templates Toggle Button (Compact)
              InkWell(
                onTap: () => setState(() => _isTemplateOpen = !_isTemplateOpen),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isTemplateOpen
                        ? AppColors.accent.withValues(alpha: 0.2)
                        : AppColors.msgSent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isTemplateOpen ? AppColors.accent : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 15,
                        color: _isTemplateOpen
                            ? AppColors.accentLight
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Шаблоны",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isTemplateOpen
                              ? AppColors.accentLight
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_currentValidationText.isNotEmpty)
            _buildBillingChip(billing),
        ],
      ),
    );
  }

  Widget _buildInputArea(List<ValidationIssue> issues) {
    final sims = ref.read(simsProvider);
    final selectedSimId = ref.watch(selectedSimProvider);
    final hasIssues = issues.isNotEmpty;
    final billing = ref.watch(smsBillingProvider(_currentValidationText));

    return Container(
      key: const ValueKey("input_area"),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: hasIssues
                ? _buildValidationBar(issues)
                : const SizedBox.shrink(),
          ),

          // Top Control Bar (Compact SIM, Templates, Billing)
          _buildInputTopBar(sims, selectedSimId, billing),

          // Text Field Input with Embedded Send Button
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 2),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.msgReceived,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasIssues
                      ? AppColors.warning.withValues(alpha: 0.5)
                      : AppColors.border,
                  width: 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  TextField(
                    controller: _controller,
                    maxLines: 10,
                    minLines: 1,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                    ),
                    spellCheckConfiguration:
                        const SpellCheckConfiguration.disabled(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.only(
                        left: 16,
                        right: 56, // Space reserved for embedded send button
                        top: 12,
                        bottom: 12,
                      ),
                      hintText: "Напишите сообщение...",
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),

                  // Embedded Send Button Inside Text Field
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Tooltip(
                      message: "Отправить сообщение",
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _send,
                          borderRadius: BorderRadius.circular(12),
                          child: Ink(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingChip(SmsBillingInfo billing) {
    final hasWarning = billing.segmentCount > 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final glowColor = hasWarning
        ? const Color(0xFFFF9800)
        : AppColors.accentLight;

    return GlassCard(
      blur: 10,
      borderRadius: 10,
      color: hasWarning
          ? const Color(0x1FFF9800)
          : (isDark ? const Color(0x14FFFFFF) : const Color(0x0A000000)),
      border: Border.all(
        color: hasWarning
            ? const Color(0xFFFF9800).withValues(alpha: 0.4)
            : AppColors.border,
        width: 1.0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Characters Info
          Icon(Icons.edit_note_rounded, size: 15, color: glowColor),
          const SizedBox(width: 6),
          Text(
            "${billing.charCount} / ${billing.maxCharsPerSegment}",
            style: TextStyle(
              color: isDark
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryLight,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),

          // Separator
          Container(
            height: 12,
            width: 1,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(width: 12),

          // Segment count info
          Icon(
            hasWarning
                ? Icons.credit_card_rounded
                : Icons.chat_bubble_outline_rounded,
            size: 15,
            color: glowColor,
          ),
          const SizedBox(width: 6),
          Text(
            "${billing.segmentCount} СМС",
            style: TextStyle(
              color: hasWarning
                  ? const Color(0xFFFF9800)
                  : (isDark
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryLight),
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),

          // Separator
          Container(
            height: 12,
            width: 1,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(width: 12),

          // Encoding info
          Icon(Icons.translate_rounded, size: 15, color: glowColor),
          const SizedBox(width: 6),
          Text(
            billing.isUnicode ? "Кириллица" : "Латиница",
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondary
                  : AppColors.textSecondaryLight,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // A compact SIM switcher for top toolbar
  Widget _buildPhysicalSimSlot(List<SimCardDto> sims, int? selectedId) {
    final activeSimIndex = sims.indexWhere(
      (s) => s.subscriptionId == selectedId,
    );
    final activeSim = activeSimIndex != -1 ? sims[activeSimIndex] : null;

    return PopupMenuButton<int>(
      onSelected: (id) {
        ref.read(selectedSimProvider.notifier).set(id);
        SfxService.playSent();
      },
      tooltip: "Выбрать SIM карту",
      color: AppColors.cardBgSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (ctx) => sims
          .map(
            (s) => PopupMenuItem(
              value: s.subscriptionId,
              child: Row(
                children: [
                  const Icon(
                    Icons.sim_card_rounded,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Slot ${s.slotIndex + 1} (${s.carrierName})",
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.msgSent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sim_card_rounded,
              size: 15,
              color: AppColors.accentLight,
            ),
            const SizedBox(width: 6),
            Text(
              "SIM ${activeSim != null ? activeSim.slotIndex + 1 : '?'}${activeSim != null ? ' (${activeSim.carrierName})' : ''}",
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateDrawer() {
    return Consumer(
      builder: (context, ref, _) {
        final templates = ref.watch(templatesProvider);
        return Container(
          width: 350,
          decoration: const BoxDecoration(
            color: AppColors.cardBgSolid,
            border: Border(left: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Drawer Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "ШАБЛОНЫ",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontFamily: 'Outfit',
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: AppColors.accentLight,
                        size: 20,
                      ),
                      onPressed: _showAddTemplateDialog,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.msgSent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border, height: 1),

              // Templates List
              Expanded(
                child: templates.isEmpty
                    ? Center(
                        child: Text(
                          "Нет сохраненных шаблонов",
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: templates.length,
                        itemBuilder: (ctx, i) {
                          final t = templates[i];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.msgReceived.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              title: Text(
                                t.title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  t.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.error,
                                  size: 18,
                                ),
                                onPressed: () {
                                  ref
                                      .read(templatesProvider.notifier)
                                      .delete(t.id);
                                  SfxService.playSent();
                                },
                              ),
                              onTap: () {
                                _controller.text = t.body;
                                setState(() => _isTemplateOpen = false);
                                SfxService.playSuccess();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddTemplateDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBgSolid,
        title: const Text(
          "Новый шаблон",
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: "Название",
                hintStyle: TextStyle(color: AppColors.textSecondary),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: "Текст сообщения",
                hintStyle: TextStyle(color: AppColors.textSecondary),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Отмена",
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty && bodyCtrl.text.isNotEmpty) {
                ref
                    .read(templatesProvider.notifier)
                    .save(
                      SmsTemplateDto(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: titleCtrl.text,
                        body: bodyCtrl.text,
                      ),
                    );
                Navigator.pop(ctx);
                SfxService.playSuccess();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
  }

  String _formatDateTimeString(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$d.$m.$y в $h:$min";
  }

  void _showContactEditDialog(ContactDto contact) {
    final nameCtrl = TextEditingController(text: contact.name);
    final notesCtrl = TextEditingController(text: contact.notes);
    final commentCtrl = TextEditingController();
    String selectedStatus = "успех";
    DateTime? selectedCallbackTime = contact.callbackTime;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBgSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Row(
            children: [
              Icon(
                contact.name.isEmpty
                    ? Icons.person_add_rounded
                    : Icons.edit_note_rounded,
                color: AppColors.accentLight,
              ),
              const SizedBox(width: 10),
              Text(
                contact.name.isEmpty ? "Подписать клиента" : "Контакт",
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 450, // Constrain width on desktop
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Номер: ${contact.phone}",
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Имя / Подпись",
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      hintText: "Напр. Иван Иванов",
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: "Заметки / Общие сведения",
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      hintText: "Напр. Клиент из Москвы, просил скидку...",
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),

                  // CRM Call History Section
                  if (contact.callHistory.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      "История звонков",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: contact.callHistory.length,
                        itemBuilder: (context, index) {
                          final record = contact.callHistory[index];
                          final dt = DateTime.fromMillisecondsSinceEpoch(
                            record.timestamp,
                          );
                          final dateStr = dt.toLocal().toString().substring(
                            5,
                            16,
                          );

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
                            default:
                              statusColor = Colors.blueAccent;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: statusColor.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Text(
                                        record.status,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                if (record.comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    record.comment,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                if (index < contact.callHistory.length - 1)
                                  const Divider(
                                    color: Colors.white10,
                                    height: 1,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // New Call Registration
                  const SizedBox(height: 20),
                  const Text(
                    "Зарегистрировать новый звонок",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedStatus,
                          dropdownColor: AppColors.cardBgSolid,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: "Статус",
                            labelStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "Дозвон",
                              child: Text("Дозвон"),
                            ),
                            DropdownMenuItem(value: "ндз", child: Text("ндз")),
                            DropdownMenuItem(
                              value: "перезвон",
                              child: Text("перезвон"),
                            ),
                            DropdownMenuItem(
                              value: "успех",
                              child: Text("успех"),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedStatus = val;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: commentCtrl,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: "Комментарий",
                            labelStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            hintText: "О чем поговорили...",
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.accent),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Scheduled Callback Picker
                  const SizedBox(height: 20),
                  const Text(
                    "Запланировать перезвон",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selectedCallbackTime != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_alarm_rounded, color: AppColors.accentLight, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Запланирован: ${_formatDateTimeString(selectedCallbackTime!)}",
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, color: AppColors.accentLight, size: 14),
                            tooltip: "Изменить",
                            onPressed: () async {
                              final result = await showDialog<DateTime>(
                                context: context,
                                builder: (ctx2) => CallbackScheduleDialog(initialDateTime: selectedCallbackTime),
                              );
                              if (result != null) {
                                setDialogState(() {
                                  selectedCallbackTime = result;
                                });
                              }
                            },
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 14),
                            tooltip: "Удалить",
                            onPressed: () {
                              setDialogState(() {
                                selectedCallbackTime = null;
                              });
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
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.calendar_today_rounded, size: 14),
                        label: const Text("Запланировать перезвон", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final result = await showDialog<DateTime>(
                            context: context,
                            builder: (ctx2) => CallbackScheduleDialog(initialDateTime: selectedCallbackTime),
                          );
                          if (result != null) {
                            setDialogState(() {
                              selectedCallbackTime = result;
                            });
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (contact.name.isNotEmpty ||
                contact.notes.isNotEmpty ||
                contact.callbackTimeMs != null ||
                contact.callHistory.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (confirmCtx) => AlertDialog(
                      backgroundColor: AppColors.cardBgSolid,
                      title: const Text("Удалить контакт?"),
                      content: const Text(
                        "Все данные контакта будут стерты из памяти.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, false),
                          child: const Text("Отмена"),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          onPressed: () => Navigator.pop(confirmCtx, true),
                          child: const Text("Стереть"),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref
                        .read(contactsProvider.notifier)
                        .delete(contact.phone);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      SfxService.playSent();
                    }
                  }
                },
                child: const Text(
                  "Удалить контакт",
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Отмена",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final List<CallRecordDto> updatedHistory = List.from(
                  contact.callHistory,
                );
                final commentText = commentCtrl.text.trim();

                // Add a new call record if comment is provided or status is not 'успех' by default (or if explicitly added)
                if (commentText.isNotEmpty ||
                    commentCtrl.text.isNotEmpty ||
                    selectedStatus != "успех") {
                  updatedHistory.add(
                    CallRecordDto(
                      timestamp: DateTime.now().millisecondsSinceEpoch,
                      comment: commentText,
                      status: selectedStatus,
                    ),
                  );
                }

                final newContact = ContactDto(
                  phone: contact.phone,
                  name: nameCtrl.text.trim(),
                  notes: notesCtrl.text.trim(),
                  callbackTimeMs: selectedCallbackTime?.millisecondsSinceEpoch,
                  callHistory: updatedHistory,
                );
                await ref.read(contactsProvider.notifier).save(newContact);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  SfxService.playSuccess();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Сохранить"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    int? threadId,
    Color startColor,
    Color endColor,
    ContactDto contact,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Unique avatar with deterministic linear gradient matching the phone
          Container(
            width: 44,
            height: 44,
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
                contact.name.isNotEmpty
                    ? contact.name.substring(0, 1).toUpperCase()
                    : "",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SelectableText(
                      contact.name.isNotEmpty ? contact.name : widget.phone,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: "Копировать номер",
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            copyToClipboard(widget.phone);
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
                                      "Номер ${widget.phone} скопирован в буфер обмена",
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppColors.cardBgSolid,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.copy_all_rounded,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.wifi_rounded,
                      size: 12,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "Мобильный хост",
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (contact.name.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SelectableText(
                        widget.phone,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (contact.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.note_alt_rounded,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            contact.notes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (contact.callbackTime != null) ...[
                  const SizedBox(height: 6),
                  Builder(
                    builder: (ctx) {
                      final isOverdue = contact.callbackTime!.isBefore(
                        DateTime.now(),
                      );
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isOverdue
                              ? AppColors.error.withValues(alpha: 0.12)
                              : AppColors.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isOverdue
                                ? AppColors.error.withValues(alpha: 0.3)
                                : AppColors.accent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_callback_rounded,
                              size: 12,
                              color: isOverdue
                                  ? AppColors.error
                                  : AppColors.accentLight,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isOverdue
                                  ? "Пропущен перезвон: ${_formatDateTime(contact.callbackTime!)}"
                                  : "Запланирован перезвон: ${_formatDateTime(contact.callbackTime!)}",
                              style: TextStyle(
                                fontSize: 11,
                                color: isOverdue
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Quick outcome selector button
                            PopupMenuButton<String>(
                              tooltip: "Результат перезвона",
                              onSelected: (outcome) {
                                DateTime? newCallbackTime;
                                String noteOutcome = "";

                                if (outcome == 'success') {
                                  noteOutcome = "Успешный перезвон";
                                  newCallbackTime = null;
                                } else if (outcome == 'no_answer') {
                                  noteOutcome = "Не ответил";
                                  newCallbackTime = DateTime.now().add(
                                    const Duration(minutes: 30),
                                  );
                                } else if (outcome == 'busy') {
                                  noteOutcome = "Занят / Сбросил";
                                  newCallbackTime = DateTime.now().add(
                                    const Duration(hours: 2),
                                  );
                                }

                                final timestamp =
                                    "${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
                                final trimmedNotes = contact.notes.trim();
                                final updatedNotes = trimmedNotes.isEmpty
                                    ? "[$timestamp] $noteOutcome"
                                    : "$trimmedNotes\n[$timestamp] $noteOutcome";

                                final updated = ContactDto(
                                  phone: contact.phone,
                                  name: contact.name,
                                  notes: updatedNotes,
                                  callbackTimeMs:
                                      newCallbackTime?.millisecondsSinceEpoch,
                                );

                                ref
                                    .read(contactsProvider.notifier)
                                    .save(updated);
                                SfxService.playSuccess();
                              },
                              offset: const Offset(0, 24),
                              color: AppColors.cardBgSolid,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'success',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.success,
                                        size: 14,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "🟢 Успешно (Дозвонился)",
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'no_answer',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.ring_volume_rounded,
                                        color: AppColors.warning,
                                        size: 14,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "🟡 Не ответил (+30 мин)",
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'busy',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.phone_locked_rounded,
                                        color: AppColors.error,
                                        size: 14,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "🔴 Занят / Сбросил (+2 ч)",
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 11,
                                      color: isOverdue
                                          ? AppColors.error
                                          : AppColors.accentLight,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Звонок совершён",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isOverdue
                                            ? AppColors.error
                                            : AppColors.accentLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 12,
                                      color: isOverdue
                                          ? AppColors.error
                                          : AppColors.accentLight,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Quick snooze button
                            PopupMenuButton<String>(
                              tooltip: "Отложить перезвон",
                              onSelected: (snoozeTime) {
                                DateTime? newCallbackTime;
                                final now = DateTime.now();

                                if (snoozeTime == '15m') {
                                  newCallbackTime = now.add(
                                    const Duration(minutes: 15),
                                  );
                                } else if (snoozeTime == '1h') {
                                  newCallbackTime = now.add(
                                    const Duration(hours: 1),
                                  );
                                } else if (snoozeTime == 'tomorrow') {
                                  newCallbackTime = now.add(
                                    const Duration(days: 1),
                                  );
                                }

                                if (newCallbackTime != null) {
                                  final updated = ContactDto(
                                    phone: contact.phone,
                                    name: contact.name,
                                    notes: contact.notes,
                                    callbackTimeMs:
                                        newCallbackTime.millisecondsSinceEpoch,
                                  );
                                  ref
                                      .read(contactsProvider.notifier)
                                      .save(updated);
                                  SfxService.playSuccess();
                                }
                              },
                              offset: const Offset(0, 24),
                              color: AppColors.cardBgSolid,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: '15m',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.more_time_rounded,
                                        color: AppColors.accentLight,
                                        size: 14,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "⏱️ +15 минут",
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: '1h',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.snooze_rounded,
                                        color: AppColors.accentLight,
                                        size: 14,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "⏱️ +1 час",
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'tomorrow',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.next_plan_rounded,
                                        color: AppColors.accentLight,
                                        size: 14,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "📅 На завтра",
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.snooze_rounded,
                                      size: 11,
                                      color: isOverdue
                                          ? AppColors.error
                                          : AppColors.accentLight,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Отложить",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isOverdue
                                            ? AppColors.error
                                            : AppColors.accentLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 12,
                                      color: isOverdue
                                          ? AppColors.error
                                          : AppColors.accentLight,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          Consumer(
            builder: (context, ref, _) {
              final activeCall = ref.watch(activeCallProvider);
              final isCurrentCall = activeCall.isInCall &&
                  activeCall.phoneNumber != null &&
                  RecipientImporter.isSamePhone(activeCall.phoneNumber!, widget.phone);

              return Tooltip(
                message: isCurrentCall ? "Сбросить звонок" : "Позвонить с телефона",
                child: IconButton(
                  icon: Icon(
                    isCurrentCall ? Icons.call_end_rounded : Icons.phone_in_talk_rounded,
                    color: isCurrentCall ? AppColors.error : Colors.greenAccent,
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: (isCurrentCall ? AppColors.error : Colors.greenAccent).withValues(alpha: 0.12),
                    hoverColor: (isCurrentCall ? AppColors.error : Colors.greenAccent).withValues(alpha: 0.22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    if (isCurrentCall) {
                      await ref.read(activeCallProvider.notifier).hangup();
                      return;
                    }
                    final subId = ref.read(selectedSimProvider) ?? -1;
                    final api = ref.read(apiClientProvider);
                    if (api != null) {
                      try {
                        ref.read(activeCallProvider.notifier).startCall(widget.phone, contactName: contact.name);
                        await api.makeCall(widget.phone, subId);
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
          const SizedBox(width: 8),

          Tooltip(
            message: contact.name.isEmpty
                ? "Подписать клиента"
                : "Редактировать пометку",
            child: IconButton(
              icon: Icon(
                contact.name.isEmpty
                    ? Icons.person_add_rounded
                    : Icons.edit_note_rounded,
                color: AppColors.accentLight,
                size: 22,
              ),
              onPressed: () => _showContactEditDialog(contact),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                hoverColor: AppColors.accent.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          if (threadId != null)
            Tooltip(
              message: "Удалить чат",
              child: IconButton(
                icon: const Icon(
                  Icons.delete_sweep_rounded,
                  color: AppColors.error,
                  size: 22,
                ),
                onPressed: () => _deleteThread(threadId),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.error.withValues(alpha: 0.08),
                  hoverColor: AppColors.error.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

          if (widget.onShowClientCard != null) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: "Показать карточку клиента",
              child: ElevatedButton.icon(
                onPressed: widget.onShowClientCard,
                icon: const Icon(Icons.badge_outlined, size: 16),
                label: const Text(
                  "Карточка клиента",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cardBgSolid,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<SmsMessageDto> messages,
    bool hasMore,
    List<SimCardDto> sims,
  ) {
    return Expanded(
      child: Stack(
        children: [
          // Elegant dot pattern backdrop
          Positioned.fill(child: CustomPaint(painter: DotPatternPainter())),

          SelectionArea(
            onSelectionChanged: WebSelectionManager.onSelectionChanged,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              itemCount: messages.length + (hasMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (hasMore && i == 0) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accent,
                        ),
                      ),
                    ),
                  );
                }
                final index = hasMore ? i - 1 : i;
                final msg = messages[index];
                bool showDate =
                    index == 0 ||
                    !_isSameDay(messages[index - 1].date, msg.date);
                return Column(
                  children: [
                    if (showDate) _buildDateLabel(msg.date),
                    MessageBubble(
                      message: msg,
                      simName: _getSimName(msg.subId, sims),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateLabel(int ms) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.msgSent.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        _formatDateLabel(ms).toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  String _getSimName(int? id, List<SimCardDto> sims) {
    if (id == null) return "SIM";
    final s = sims.where((e) => e.subscriptionId == id);
    return s.isNotEmpty ? s.first.carrierName : "SIM";
  }

  Future<void> _deleteThread(int threadId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBgSolid,
        title: const Text(
          "Удалить чат?",
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Эта переписка будет навсегда удалена с вашего телефона.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Отмена",
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(apiClientProvider)?.deleteThread(threadId);
        if (!mounted) return;
        final remaining = ref
            .read(allMessagesProvider)
            .where((m) => m.threadId != threadId)
            .toList();
        ref.read(allMessagesProvider.notifier).set(remaining);
        ref.read(selectedChatIdProvider.notifier).select(null);
        SfxService.playSent();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Ошибка удаления: $e",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return "$day.$month в $hour:$minute";
  }
}
