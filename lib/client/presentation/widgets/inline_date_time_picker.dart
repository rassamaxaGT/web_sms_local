import 'package:flutter/material.dart';
import '../../../shared/theme.dart';

class InlineDateTimePicker extends StatefulWidget {
  final DateTime? initialDateTime;
  final ValueChanged<DateTime?> onChanged;

  const InlineDateTimePicker({
    super.key,
    required this.initialDateTime,
    required this.onChanged,
  });

  @override
  State<InlineDateTimePicker> createState() => _InlineDateTimePickerState();
}

class _InlineDateTimePickerState extends State<InlineDateTimePicker> {
  late bool isScheduled;
  late DateTime focusedMonth;
  late DateTime selectedDate;
  late TimeOfDay selectedTime;

  late final TextEditingController dateCtrl;
  late final TextEditingController timeCtrl;

  static const List<String> _russianMonths = [
    "",
    "Январь",
    "Февраль",
    "Март",
    "Апрель",
    "Май",
    "Июнь",
    "Июль",
    "Август",
    "Сентябрь",
    "Октябрь",
    "Ноябрь",
    "Декабрь",
  ];

  static const List<String> _weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

  @override
  void initState() {
    super.initState();
    isScheduled = widget.initialDateTime != null;
    
    final baseDateTime = widget.initialDateTime ?? DateTime.now();
    focusedMonth = DateTime(baseDateTime.year, baseDateTime.month);
    selectedDate = DateTime(baseDateTime.year, baseDateTime.month, baseDateTime.day);
    selectedTime = TimeOfDay.fromDateTime(baseDateTime);

    dateCtrl = TextEditingController(text: _formatDate(selectedDate));
    timeCtrl = TextEditingController(text: _formatTime(selectedTime));
  }

  @override
  void dispose() {
    dateCtrl.dispose();
    timeCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
  }

  String _formatTime(TimeOfDay time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  DateTime? _parseDate(String text) {
    final parts = text.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year < 100) {
      year += 2000;
    }
    if (day < 1 || day > 31 || month < 1 || month > 12 || year < 2000) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  TimeOfDay? _parseTime(String text) {
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _notifyChange() {
    if (!isScheduled) {
      widget.onChanged(null);
    } else {
      widget.onChanged(
        DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          selectedTime.hour,
          selectedTime.minute,
        ),
      );
    }
  }

  List<DateTime> _buildCalendarDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = firstDay.weekday - 1; // 0 for Mon, 6 for Sun
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    
    final List<DateTime> days = [];
    
    // Padding from previous month
    final prevMonthEnd = DateTime(month.year, month.month, 0).day;
    for (int i = startOffset - 1; i >= 0; i--) {
      days.add(DateTime(month.year, month.month - 1, prevMonthEnd - i));
    }
    
    // Current month days
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(month.year, month.month, i));
    }
    
    // Padding from next month
    const totalCells = 42;
    final nextPadding = totalCells - days.length;
    for (int i = 1; i <= nextPadding; i++) {
      days.add(DateTime(month.year, month.month + 1, i));
    }
    
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final calendarDays = _buildCalendarDays(focusedMonth);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBgSolid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Radio buttons
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    isScheduled = false;
                    _notifyChange();
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: !isScheduled ? AppColors.accent : AppColors.textSecondary,
                          width: 2,
                        ),
                      ),
                      child: !isScheduled
                          ? const Center(
                              child: SizedBox(
                                width: 8,
                                height: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Сейчас",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () {
                  setState(() {
                    isScheduled = true;
                    _notifyChange();
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isScheduled ? AppColors.accent : AppColors.textSecondary,
                          width: 2,
                        ),
                      ),
                      child: isScheduled
                          ? const Center(
                              child: SizedBox(
                                width: 8,
                                height: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Запланировать",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isScheduled ? 1.0 : 0.3,
            child: IgnorePointer(
              ignoring: !isScheduled,
              child: Column(
                children: [
                  // Month/Year Switcher Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${_russianMonths[focusedMonth.month]} ${focusedMonth.year}",
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
                            onPressed: () {
                              setState(() {
                                focusedMonth = DateTime(focusedMonth.year, focusedMonth.month - 1);
                              });
                            },
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onPressed: () {
                              setState(() {
                                focusedMonth = DateTime(focusedMonth.year, focusedMonth.month + 1);
                              });
                            },
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Weekdays Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _weekdays.asMap().entries.map((entry) {
                      final isWeekend = entry.key == 5 || entry.key == 6;
                      return Expanded(
                        child: Center(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              color: isWeekend ? AppColors.error : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  // Calendar Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: 42,
                    itemBuilder: (context, index) {
                      final dayDate = calendarDays[index];
                      final isCurrentMonth = dayDate.month == focusedMonth.month;
                      final isSelected = dayDate.year == selectedDate.year &&
                                         dayDate.month == selectedDate.month &&
                                         dayDate.day == selectedDate.day;
                      final isToday = dayDate.year == DateTime.now().year &&
                                      dayDate.month == DateTime.now().month &&
                                      dayDate.day == DateTime.now().day;
                      final isWeekend = dayDate.weekday == 6 || dayDate.weekday == 7;

                      Color textColor;
                      if (isSelected) {
                        textColor = Colors.white;
                      } else if (isCurrentMonth) {
                        textColor = isWeekend ? AppColors.error : AppColors.textPrimary;
                      } else {
                        textColor = AppColors.textSecondary.withValues(alpha: 0.3);
                      }

                      return InkWell(
                        onTap: () {
                          setState(() {
                            selectedDate = dayDate;
                            dateCtrl.text = _formatDate(selectedDate);
                            _notifyChange();
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accent : Colors.transparent,
                            shape: BoxShape.circle,
                            border: isToday && !isSelected
                                ? Border.all(color: AppColors.accent, width: 1.5)
                                : null,
                          ),
                          child: Text(
                            dayDate.day.toString(),
                            style: TextStyle(
                              color: textColor,
                              fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date & Time Input Fields Row
                  Row(
                    children: [
                      // Date Input Field
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Дата",
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: dateCtrl,
                              onChanged: (val) {
                                final parsed = _parseDate(val);
                                if (parsed != null) {
                                  setState(() {
                                    selectedDate = parsed;
                                    focusedMonth = DateTime(parsed.year, parsed.month);
                                    _notifyChange();
                                  });
                                }
                              },
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                hintText: "дд.мм.гггг",
                                hintStyle: const TextStyle(color: AppColors.textSecondary),
                                suffixIcon: const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textSecondary),
                                suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: AppColors.accent),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Time Input Field
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Время клиента",
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: timeCtrl,
                              onChanged: (val) {
                                final parsed = _parseTime(val);
                                if (parsed != null) {
                                  setState(() {
                                    selectedTime = parsed;
                                    _notifyChange();
                                  });
                                }
                              },
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                hintText: "чч:мм",
                                hintStyle: const TextStyle(color: AppColors.textSecondary),
                                suffixIcon: const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textSecondary),
                                suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: AppColors.accent),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
