// lib/client/presentation/views/broadcast/broadcast_monitor_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/shared_models.dart';
import '../../../../shared/theme.dart';
import '../../../logic/providers.dart';

class BroadcastMonitorView extends ConsumerStatefulWidget {
  final String campaignId;
  final VoidCallback? onBack;

  const BroadcastMonitorView({
    super.key,
    required this.campaignId,
    this.onBack,
  });

  @override
  ConsumerState<BroadcastMonitorView> createState() => _BroadcastMonitorViewState();
}

class _BroadcastMonitorViewState extends ConsumerState<BroadcastMonitorView> {
  String _itemStatusFilter = 'all'; // 'all', 'sent', 'failed', 'pending'

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(campaignsProvider);
    final campaign = campaigns.firstWhere(
      (c) => c.id == widget.campaignId,
      orElse: () => CampaignDto(
        id: widget.campaignId,
        title: "Загрузка...",
        createdAtMs: 0,
        updatedAtMs: 0,
        templateBody: "",
      ),
    );

    final isRunning = campaign.status == 'running';
    final isPaused = campaign.status == 'paused';
    final isCompleted = campaign.status == 'completed';

    // Filter items
    final filteredItems = campaign.items.where((item) {
      if (_itemStatusFilter == 'sent') return item.status == 'sent';
      if (_itemStatusFilter == 'failed') return item.status == 'failed';
      if (_itemStatusFilter == 'pending') return item.status == 'pending' || item.status == 'sending';
      return true;
    }).toList();

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Top Navigation & Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.transparent,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black26,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              campaign.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Outfit',
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildStatusBadge(campaign.status),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Создана ${_formatDate(campaign.createdAtMs)} • Интервал: ${campaign.intervalSeconds}с",
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),

                // Control Action Buttons
                if (isRunning) ...[
                  ElevatedButton.icon(
                    onPressed: () => ref.read(campaignsProvider.notifier).pause(campaign.id),
                    icon: const Icon(Icons.pause_rounded, size: 16),
                    label: const Text("Пауза"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ] else if (isPaused || campaign.status == 'draft' || campaign.status == 'queued') ...[
                  ElevatedButton.icon(
                    onPressed: () => ref.read(campaignsProvider.notifier).start(campaign.id),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text("Запустить"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],

                if (isRunning || isPaused) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(campaignsProvider.notifier).stop(campaign.id),
                    icon: const Icon(Icons.stop_rounded, size: 16),
                    label: const Text("Остановить"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],

                if (campaign.failedCount > 0 && !isRunning) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => ref.read(campaignsProvider.notifier).retryFailed(campaign.id),
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: Text("Повторить ошибки (${campaign.failedCount})"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentLight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],

                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _exportCsvReport(context, campaign),
                  icon: const Icon(Icons.download_rounded, color: AppColors.textPrimary, size: 20),
                  tooltip: "Экспорт отчета в CSV",
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black26,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          // Main Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Прогресс выполнения",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Text(
                              "${(campaign.progressPercentage * 100).toStringAsFixed(1)}%",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.accent, fontFamily: 'Outfit'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: campaign.progressPercentage,
                            minHeight: 10,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isCompleted
                                  ? AppColors.success
                                  : campaign.failedCount > 0 && campaign.sentCount == 0
                                      ? AppColors.error
                                      : AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 4 Stat Cards
                        Row(
                          children: [
                            _buildStatMetric("Всего", "${campaign.totalCount}", AppColors.textPrimary, Icons.people_outline_rounded),
                            const SizedBox(width: 10),
                            _buildStatMetric("Отправлено", "${campaign.sentCount}", AppColors.success, Icons.check_circle_outline_rounded),
                            const SizedBox(width: 10),
                            _buildStatMetric("Ошибок", "${campaign.failedCount}", AppColors.error, Icons.error_outline_rounded),
                            const SizedBox(width: 10),
                            _buildStatMetric("В очереди", "${campaign.pendingCount}", AppColors.textSecondary, Icons.hourglass_empty_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Execution Log Header & Filter Chips
                  Row(
                    children: [
                      const Text(
                        "ЖУРНАЛ ОТПРАВКИ",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontFamily: 'Outfit',
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      _buildFilterChip('all', "Все (${campaign.items.length})"),
                      const SizedBox(width: 6),
                      _buildFilterChip('sent', "Успешно (${campaign.sentCount})"),
                      const SizedBox(width: 6),
                      _buildFilterChip('failed', "Ошибки (${campaign.failedCount})"),
                      const SizedBox(width: 6),
                      _buildFilterChip('pending', "В очереди (${campaign.pendingCount})"),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Items List / Table
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: filteredItems.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Text("В этой категории нет получателей", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredItems.length,
                            separatorBuilder: (context, i) => const Divider(color: AppColors.border, height: 1),
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return _buildItemRow(index + 1, item);
                            },
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

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'running':
        bg = AppColors.accent.withValues(alpha: 0.2);
        fg = AppColors.accent;
        label = "Выполняется 🟢";
        break;
      case 'paused':
        bg = AppColors.warning.withValues(alpha: 0.2);
        fg = AppColors.accentLight;
        label = "На паузе ⏸️";
        break;
      case 'completed':
        bg = AppColors.success.withValues(alpha: 0.2);
        fg = AppColors.success;
        label = "Завершена ✅";
        break;
      case 'cancelled':
        bg = AppColors.error.withValues(alpha: 0.2);
        fg = AppColors.error;
        label = "Остановлена ⏹️";
        break;
      default:
        bg = Colors.white10;
        fg = AppColors.textSecondary;
        label = "Черновик";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildStatMetric(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color, fontFamily: 'Outfit')),
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _itemStatusFilter == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppColors.textSecondary)),
      selected: isSelected,
      onSelected: (val) => setState(() => _itemStatusFilter = key),
      selectedColor: AppColors.accent,
      backgroundColor: Colors.black26,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildItemRow(int num, CampaignItemDto item) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (item.status) {
      case 'sent':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        statusText = "Отправлено";
        break;
      case 'failed':
        statusColor = AppColors.error;
        statusIcon = Icons.cancel_rounded;
        statusText = "Ошибка";
        break;
      case 'sending':
        statusColor = AppColors.accent;
        statusIcon = Icons.sync_rounded;
        statusText = "Отправка...";
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.schedule_rounded;
        statusText = "В очереди";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Index number
          SizedBox(
            width: 28,
            child: Text(
              "$num",
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
            ),
          ),

          // Status Icon
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 10),

          // Recipient Phone & Name
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.phone,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                if (item.name != null && item.name!.isNotEmpty)
                  Text(
                    item.name!,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Message Text
          Expanded(
            child: Text(
              item.interpolatedText,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 12),

          // Error tooltip or Status label
          if (item.errorMessage != null)
            Tooltip(
              message: item.errorMessage!,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 12, color: AppColors.error),
                    const SizedBox(width: 4),
                    Text(statusText, style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          else
            Text(statusText, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _exportCsvReport(BuildContext context, CampaignDto campaign) {
    final buffer = StringBuffer();
    buffer.writeln("phone,name,status,parts_count,sent_at,error");

    for (final item in campaign.items) {
      final sentDate = item.sentAtMs != null ? _formatDate(item.sentAtMs!) : "";
      final err = (item.errorMessage ?? "").replaceAll(',', ';').replaceAll('\n', ' ');
      final name = (item.name ?? "").replaceAll(',', ';');
      buffer.writeln("${item.phone},$name,${item.status},${item.partsCount},$sentDate,$err");
    }

    final csvContent = buffer.toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBgSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Отчет рассылки (CSV)", style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Скопируйте текст отчета для открытия в Excel или сохранения в файл:", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: TextEditingController(text: csvContent),
                maxLines: 8,
                readOnly: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Закрыть", style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  String _formatDate(int ms) {
    if (ms == 0) return "-";
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
