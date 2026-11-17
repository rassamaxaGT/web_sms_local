import 'package:flutter/material.dart';
import '../../../shared/theme.dart';

class CallbackScheduleDialog extends StatefulWidget {
  final DateTime? initialDateTime;

  const CallbackScheduleDialog({
    super.key,
    required this.initialDateTime,
  });

  @override
  State<CallbackScheduleDialog> createState() => _CallbackScheduleDialogState();
}

class _CallbackScheduleDialogState extends State<CallbackScheduleDialog> {
  late DateTime focusedMonth;
  late DateTime selectedDate;
  late TimeOfDay selectedTime;
  String? _timeError;

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
    
    final baseDateTime = widget.initialDateTime ?? DateTime.now().add(const Duration(hours: 1));
    focusedMonth = DateTime(baseDateTime.year, baseDateTime.month);
    selectedDate = DateTime(baseDateTime.year, baseDateTime.month, baseDateTime.day);
    selectedTime = TimeOfDay.fromDateTime(baseDateTime);

    dateCtrl = TextEditingController(text: _formatDate(selectedDate));
    timeCtrl = TextEditingController(text: _formatTime(selectedTime));
    _timeError = null;
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

    return Dialog(
      backgroundColor: AppColors.cardBgSolid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Запланировать перезвон",
                  style: TextStyle(
                    color: AppColors.accentLight,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(width: 12),
                // Time Input Field
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Время",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: timeCtrl,
                        onChanged: (val) {
                          final digits = val.replaceAll(RegExp(r'\D'), '');
                          if (digits.length == 4) {
                            final h = int.tryParse(digits.substring(0, 2)) ?? -1;
                            final m = int.tryParse(digits.substring(2, 4)) ?? -1;
                            if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
                              final formatted = "${digits.substring(0, 2)}:${digits.substring(2, 4)}";
                              timeCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(offset: formatted.length),
                              );
                              setState(() {
                                selectedTime = TimeOfDay(hour: h, minute: m);
                                _timeError = null;
                              });
                            } else {
                              setState(() {
                                _timeError = "Неверное время (00:00 - 23:59)";
                              });
                            }
                          } else if (digits.length < 4) {
                            setState(() {
                              _timeError = "Введите 4 цифры (например, 1230)";
                            });
                          } else {
                            final truncated = digits.substring(0, 4);
                            final formatted = "${truncated.substring(0, 2)}:${truncated.substring(2, 4)}";
                            timeCtrl.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(offset: formatted.length),
                            );
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
                            borderSide: BorderSide(color: _timeError != null ? AppColors.error : AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: _timeError != null ? AppColors.error : AppColors.accent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Error Text Area
            if (_timeError != null) ...[
              const SizedBox(height: 8),
              Text(
                _timeError!,
                style: const TextStyle(color: AppColors.error, fontSize: 11),
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Отмена", style: TextStyle(color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: _timeError == null && timeCtrl.text.isNotEmpty
                      ? () {
                          Navigator.of(context).pop(
                            DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              selectedTime.hour,
                              selectedTime.minute,
                            ),
                          );
                        }
                      : null,
                  child: const Text("Сохранить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
