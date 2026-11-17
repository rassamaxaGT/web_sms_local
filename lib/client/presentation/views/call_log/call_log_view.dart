// lib/client/presentation/views/call_log/call_log_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/shared_models.dart';
import '../../../../shared/theme.dart';
import '../../../logic/providers.dart';
import '../../../utils/recipient_importer.dart';

enum CallFilter { all, incoming, outgoing, missed }

class CallLogDayGroup {
  final DateTime dateMidnight;
  final String dateTitle;
  final String dateSubtitle;
  final List<CallLogEntryDto> calls;
  final int totalTalkDurationSeconds;
  final int dialoguesCount;
  final int incomingCount;
  final int outgoingCount;
  final int missedCount;

  CallLogDayGroup({
    required this.dateMidnight,
    required this.dateTitle,
    required this.dateSubtitle,
    required this.calls,
    required this.totalTalkDurationSeconds,
    required this.dialoguesCount,
    required this.incomingCount,
    required this.outgoingCount,
    required this.missedCount,
  });
}

class CallLogView extends ConsumerStatefulWidget {
  const CallLogView({super.key});

  @override
  ConsumerState<CallLogView> createState() => _CallLogViewState();
}

class _CallLogViewState extends ConsumerState<CallLogView> {
  CallFilter _currentFilter = CallFilter.all;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(callLogsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await ref.read(callLogsProvider.notifier).load();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return "00:00";
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _formatDurationHuman(int seconds) {
    if (seconds <= 0) return "0 сек";
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final parts = <String>[];
    if (h > 0) parts.add("$h ч");
    if (m > 0) parts.add("$m мин");
    if (s > 0 || parts.isEmpty) parts.add("$s сек");
    return parts.join(" ");
  }

  String _formatCallTime(int ms) {
    if (ms <= 0) return "—";
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  bool _isMissedCall(CallLogEntryDto call) {
    final status = call.status.toLowerCase();
    return status == 'пропущен' ||
        status == 'ндз' ||
        status == 'сброшен' ||
        status == 'отклонен' ||
        (call.direction == 'incoming' && call.durationSeconds == 0);
  }

  List<CallLogDayGroup> _groupCallsByDay(List<CallLogEntryDto> calls) {
    if (calls.isEmpty) return [];

    final Map<int, List<CallLogEntryDto>> groups = {};
    for (final call in calls) {
      final validMs = call.date > 0 ? call.date : DateTime.now().millisecondsSinceEpoch;
      final dt = DateTime.fromMillisecondsSinceEpoch(validMs);
      final midnight = DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
      groups.putIfAbsent(midnight, () => []).add(call);
    }

    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final yesterdayMidnight = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;

    const months = [
      "января", "февраля", "марта", "апреля", "мая", "июня",
      "июля", "августа", "сентября", "октября", "ноября", "декабря"
    ];
    const weekdays = [
      "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"
    ];

    return sortedKeys.map((key) {
      final dayCalls = groups[key]!;
      dayCalls.sort((a, b) => b.date.compareTo(a.date));

      final dt = DateTime.fromMillisecondsSinceEpoch(key);
      String title;
      String subtitle;

      if (key == todayMidnight) {
        title = "Сегодня, ${dt.day} ${months[dt.month - 1]}";
        subtitle = weekdays[dt.weekday - 1];
      } else if (key == yesterdayMidnight) {
        title = "Вчера, ${dt.day} ${months[dt.month - 1]}";
        subtitle = weekdays[dt.weekday - 1];
      } else {
        title = "${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}";
        subtitle = dt.year == now.year ? "" : "${dt.year} г.";
      }

      int totalTalkDuration = 0;
      int dialoguesCount = 0;
      int incoming = 0;
      int outgoing = 0;
      int missed = 0;

      for (final c in dayCalls) {
        if (c.durationSeconds > 0) {
          totalTalkDuration += c.durationSeconds;
          dialoguesCount++;
        }
        if (c.direction == 'incoming') {
          incoming++;
        } else {
          outgoing++;
        }
        if (_isMissedCall(c)) {
          missed++;
        }
      }

      return CallLogDayGroup(
        dateMidnight: dt,
        dateTitle: title,
        dateSubtitle: subtitle,
        calls: dayCalls,
        totalTalkDurationSeconds: totalTalkDuration,
        dialoguesCount: dialoguesCount,
        incomingCount: incoming,
        outgoingCount: outgoing,
        missedCount: missed,
      );
    }).toList();
  }

  Widget _buildStatusBadge(CallLogEntryDto call) {
    final isIncoming = call.direction == 'incoming';
    final status = call.status.toLowerCase();

    Color color;
    String label;
    IconData icon;

    if (isIncoming) {
      if (status == 'пропущен') {
        color = AppColors.error;
        label = 'Пропущен';
        icon = Icons.call_missed_rounded;
      } else if (status == 'сброшен' || status == 'отклонен') {
        color = Colors.orangeAccent;
        label = 'Сброшен';
        icon = Icons.phone_disabled_rounded;
      } else if (call.durationSeconds > 0 || status == 'принят' || status == 'успех') {
        color = const Color(0xFF10B981);
        label = 'Принят';
        icon = Icons.call_received_rounded;
      } else {
        color = AppColors.textSecondary;
        label = 'Без ответа';
        icon = Icons.call_missed_rounded;
      }
    } else {
      if (call.durationSeconds > 0 || status == 'успех' || status == 'дозвон') {
        color = const Color(0xFF10B981);
        label = 'Дозвон';
        icon = Icons.call_made_rounded;
      } else if (status == 'ндз') {
        color = AppColors.error;
        label = 'НДЗ';
        icon = Icons.phone_missed_rounded;
      } else if (status == 'перезвон') {
        color = AppColors.accentLight;
        label = 'Перезвон';
        icon = Icons.phone_callback_rounded;
      } else {
        color = AppColors.textSecondary;
        label = 'Исходящий';
        icon = Icons.call_made_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allCalls = ref.watch(callLogsProvider);
    final contacts = ref.watch(contactsProvider);

    // Apply Filter & Search
    final filtered = allCalls.where((call) {
      if (_currentFilter == CallFilter.incoming && call.direction != 'incoming') {
        return false;
      }
      if (_currentFilter == CallFilter.outgoing && call.direction != 'outgoing') {
        return false;
      }
      if (_currentFilter == CallFilter.missed && !_isMissedCall(call)) {
        return false;
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchPhone = call.number.toLowerCase().contains(query);
        final matchName = call.name?.toLowerCase().contains(query) ?? false;
        final matchComment = call.comment?.toLowerCase().contains(query) ?? false;
        if (!matchPhone && !matchName && !matchComment) return false;
      }
      return true;
    }).toList();

    // Compute Today's Stats (only for current day)
    final now = DateTime.now();
    final todayStartMs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final todayCalls = allCalls.where((c) => c.date >= todayStartMs).toList();

    final totalCount = todayCalls.length;
    final totalTalkSec = todayCalls.fold<int>(
      0,
      (sum, c) => sum + (c.durationSeconds > 0 ? c.durationSeconds : 0),
    );
    final incomingCount = todayCalls.where((c) => c.direction == 'incoming').length;
    final outgoingCount = todayCalls.where((c) => c.direction == 'outgoing').length;
    final missedCount = todayCalls.where((c) => _isMissedCall(c)).length;

    // Group filtered calls by day
    final dayGroups = _groupCallsByDay(filtered);

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Top Header Bar
          _buildHeaderBar(context),

          // KPI Stats Row with Total Talk Time
          _buildKpiRow(totalCount, totalTalkSec, incomingCount, outgoingCount, missedCount),

          // Filters & Search ToolBar
          _buildFilterBar(),

          // Main Call Log List Grouped by Day
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : _buildGroupedCallList(dayGroups, contacts),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.phone_in_talk_rounded,
              color: AppColors.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "ЖУРНАЛ ЗВОНКОВ",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontFamily: 'Outfit',
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "История вызовов с группировкой по датам и статистикой времени в диалоге",
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _isRefreshing ? null : _refresh,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Обновить"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(int total, int totalTalkSec, int incoming, int outgoing, int missed) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          _buildKpiCard("Звонков сегодня", "$total", Icons.phone_rounded, AppColors.accent),
          const SizedBox(width: 12),
          _buildKpiCard(
            "В диалоге (сегодня)",
            _formatDurationHuman(totalTalkSec),
            Icons.record_voice_over_rounded,
            const Color(0xFF10B981),
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            "Входящие",
            "$incoming",
            Icons.call_received_rounded,
            const Color(0xFF10B981),
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            "Исходящие",
            "$outgoing",
            Icons.call_made_rounded,
            Colors.blueAccent,
          ),
          const SizedBox(width: 12),
          _buildKpiCard(
            "Пропущенные",
            "$missed",
            Icons.call_missed_rounded,
            AppColors.error,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _buildFilterChip("Все", CallFilter.all),
          const SizedBox(width: 8),
          _buildFilterChip("Входящие", CallFilter.incoming),
          const SizedBox(width: 8),
          _buildFilterChip("Исходящие", CallFilter.outgoing),
          const SizedBox(width: 8),
          _buildFilterChip("Пропущенные", CallFilter.missed),
          const Spacer(),

          // Search Field
          SizedBox(
            width: 280,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Поиск по номеру или имени...",
                hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: AppColors.textSecondary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.cardBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, CallFilter filter) {
    final isSelected = _currentFilter == filter;
    return InkWell(
      onTap: () => setState(() => _currentFilter = filter),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDayGroupHeader(CallLogDayGroup group) {
    final talkTimeStr = _formatDurationHuman(group.totalTalkDurationSeconds);

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: AppColors.accentLight,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.dateTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                  color: AppColors.textPrimary,
                ),
              ),
              if (group.dateSubtitle.isNotEmpty)
                Text(
                  group.dateSubtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const Spacer(),

          // Daily Talk Time Badge (Highlight)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: group.totalTalkDurationSeconds > 0
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : AppColors.border.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: group.totalTalkDurationSeconds > 0
                    ? const Color(0xFF10B981).withValues(alpha: 0.35)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.record_voice_over_rounded,
                  size: 14,
                  color: group.totalTalkDurationSeconds > 0
                      ? const Color(0xFF10B981)
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  "В диалоге: $talkTimeStr",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: group.totalTalkDurationSeconds > 0
                        ? const Color(0xFF10B981)
                        : AppColors.textSecondary,
                  ),
                ),
                if (group.dialoguesCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    "(${group.dialoguesCount} разг.)",
                    style: TextStyle(
                      fontSize: 11,
                      color: group.totalTalkDurationSeconds > 0
                          ? const Color(0xFF10B981).withValues(alpha: 0.8)
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Daily Counts Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Всего: ${group.calls.length}",
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(width: 1, height: 10, color: AppColors.border),
                const SizedBox(width: 6),
                const Icon(Icons.call_received_rounded, size: 11, color: Color(0xFF10B981)),
                const SizedBox(width: 2),
                Text(
                  "${group.incomingCount}",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.call_made_rounded, size: 11, color: Colors.blueAccent),
                const SizedBox(width: 2),
                Text(
                  "${group.outgoingCount}",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (group.missedCount > 0) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.call_missed_rounded, size: 11, color: AppColors.error),
                  const SizedBox(width: 2),
                  Text(
                    "${group.missedCount}",
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedCallList(
    List<CallLogDayGroup> dayGroups,
    List<ContactDto> contacts,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      itemCount: dayGroups.length,
      itemBuilder: (context, index) {
        final group = dayGroups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDayGroupHeader(group),
            ...group.calls.map(
              (call) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildCallCard(context, call, contacts),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCallCard(
    BuildContext context,
    CallLogEntryDto call,
    List<ContactDto> contacts,
  ) {
    final isIncoming = call.direction == 'incoming';
    final isMissed = _isMissedCall(call);

    // Resolve Contact Name: only add name if not specified in Android call log, but present in app
    ContactDto? matchedContact;
    for (var c in contacts) {
      if (RecipientImporter.isSamePhone(c.phone, call.number)) {
        matchedContact = c;
        break;
      }
    }
    final hasAndroidName = call.name != null && call.name!.trim().isNotEmpty;
    final displayName = hasAndroidName
        ? call.name!.trim()
        : (matchedContact?.name.trim().isNotEmpty == true
            ? matchedContact!.name.trim()
            : "Неизвестный");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMissed
              ? AppColors.error.withValues(alpha: 0.25)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Direction Icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isMissed
                  ? AppColors.error.withValues(alpha: 0.15)
                  : (isIncoming ? const Color(0xFF10B981) : Colors.blueAccent)
                      .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMissed
                  ? Icons.call_missed_rounded
                  : (isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded),
              color: isMissed
                  ? AppColors.error
                  : (isIncoming ? const Color(0xFF10B981) : Colors.blueAccent),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Contact Name & Phone
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (matchedContact == null && displayName == "Неизвестный") ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          ref.read(selectedChatIdProvider.notifier).select(call.number);
                          ref.read(activeViewModeProvider.notifier).set(AppViewMode.chats);
                        },
                        child: const Text(
                          "+ Подписать",
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.accentLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      call.number,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: call.number));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Номер ${call.number} скопирован"),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Exact Time
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatCallTime(call.date),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isIncoming ? "Входящий звонок" : "Исходящий звонок",
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Duration in dialogue
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (call.durationSeconds > 0)
                      const Icon(
                        Icons.record_voice_over_rounded,
                        size: 13,
                        color: Color(0xFF10B981),
                      ),
                    if (call.durationSeconds > 0) const SizedBox(width: 4),
                    Text(
                      _formatDuration(call.durationSeconds),
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        color: call.durationSeconds > 0
                            ? const Color(0xFF10B981)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  call.durationSeconds > 0 ? "в диалоге" : "без ответа",
                  style: TextStyle(
                    fontSize: 10,
                    color: call.durationSeconds > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.8)
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Status Badge
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(call),
            ),
          ),

          // CRM Comment (if present)
          if (call.comment != null && call.comment!.isNotEmpty)
            Expanded(
              flex: 2,
              child: Text(
                call.comment!,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          const SizedBox(width: 12),

          // Quick Action: Call Button
          Tooltip(
            message: "Позвонить",
            child: IconButton(
              icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
              color: const Color(0xFF10B981),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.12),
                hoverColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(8),
              ),
              onPressed: () async {
                final api = ref.read(apiClientProvider);
                final subId = ref.read(selectedSimProvider) ?? -1;
                if (api != null) {
                  ref.read(activeCallProvider.notifier).startCall(
                        call.number,
                        contactName: displayName != "Неизвестный" ? displayName : null,
                      );
                  await api.makeCall(call.number, subId);
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // Quick Action: Open Chat
          Tooltip(
            message: "Перейти к сообщениям",
            child: IconButton(
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              color: AppColors.accentLight,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                hoverColor: AppColors.accent.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(8),
              ),
              onPressed: () {
                ref.read(selectedChatIdProvider.notifier).select(call.number);
                ref.read(activeViewModeProvider.notifier).set(AppViewMode.chats);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.phone_missed_rounded,
              size: 48,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "Звонков не найдено",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "В журнале пока нет вызовов, соответствующих выбранному фильтру.",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
