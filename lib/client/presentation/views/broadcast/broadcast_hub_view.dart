// lib/client/presentation/views/broadcast/broadcast_hub_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/shared_models.dart';
import '../../../../shared/theme.dart';
import '../../../logic/providers.dart';
import 'broadcast_wizard_dialog.dart';
import 'broadcast_monitor_view.dart';

class BroadcastHubView extends ConsumerWidget {
  const BroadcastHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCampaignId = ref.watch(selectedCampaignIdProvider);
    final campaigns = ref.watch(campaignsProvider);

    // If a campaign is actively selected to view details/monitor
    if (selectedCampaignId != null) {
      return BroadcastMonitorView(
        campaignId: selectedCampaignId,
        onBack: () => ref.read(selectedCampaignIdProvider.notifier).select(null),
      );
    }

    // Otherwise show Campaigns Hub (List & Management)
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Header Bar
          Container(
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
                  child: const Icon(Icons.campaign_rounded, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "МАССОВЫЕ РАССЫЛКИ",
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
                      "Автономная отправка персонализированных SMS через Android Host",
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),

                // Create Campaign Button
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => const BroadcastWizardDialog(),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text("Новая рассылка"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          // Campaigns List Content
          Expanded(
            child: campaigns.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: campaigns.length,
                    itemBuilder: (context, index) {
                      final campaign = campaigns[index];
                      return _buildCampaignCard(context, ref, campaign);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 64,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Нет активных рассылок",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Создайте свою первую кампанию для автоматической отправки персонализированных SMS группе клиентов.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const BroadcastWizardDialog(),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text("Создать рассылку"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignCard(BuildContext context, WidgetRef ref, CampaignDto campaign) {
    final isRunning = campaign.status == 'running';
    final isPaused = campaign.status == 'paused';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border,
          width: isRunning ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          ref.read(selectedCampaignIdProvider.notifier).select(campaign.id);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title + Status Badge + Actions
              Row(
                children: [
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildStatusBadge(campaign.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Создана ${_formatDate(campaign.createdAtMs)} • ${campaign.totalCount} получателей",
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  // Quick Action Buttons
                  if (isRunning) ...[
                    IconButton(
                      onPressed: () => ref.read(campaignsProvider.notifier).pause(campaign.id),
                      icon: const Icon(Icons.pause_circle_rounded, color: AppColors.warning, size: 24),
                      tooltip: "Поставить на паузу",
                    ),
                  ] else if (isPaused || campaign.status == 'draft' || campaign.status == 'queued') ...[
                    IconButton(
                      onPressed: () => ref.read(campaignsProvider.notifier).start(campaign.id),
                      icon: const Icon(Icons.play_circle_rounded, color: AppColors.accent, size: 24),
                      tooltip: "Запустить",
                    ),
                  ],

                  if (campaign.failedCount > 0 && !isRunning) ...[
                    IconButton(
                      onPressed: () => ref.read(campaignsProvider.notifier).retryFailed(campaign.id),
                      icon: const Icon(Icons.replay_rounded, color: AppColors.accentLight, size: 20),
                      tooltip: "Повторить неотправленные",
                    ),
                  ],

                  IconButton(
                    onPressed: () => _confirmDelete(context, ref, campaign),
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary, size: 20),
                    tooltip: "Удалить рассылку",
                  ),

                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),

              const SizedBox(height: 14),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: campaign.progressPercentage,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    campaign.status == 'completed'
                        ? AppColors.success
                        : isRunning
                            ? AppColors.accent
                            : AppColors.accentLight,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Stats Row
              Row(
                children: [
                  _buildStatItem("Отправлено", "${campaign.sentCount}", AppColors.success),
                  const SizedBox(width: 16),
                  _buildStatItem("Ошибок", "${campaign.failedCount}", campaign.failedCount > 0 ? AppColors.error : AppColors.textSecondary),
                  const SizedBox(width: 16),
                  _buildStatItem("В очереди", "${campaign.pendingCount}", AppColors.textSecondary),
                  const Spacer(),
                  Text(
                    "${(campaign.progressPercentage * 100).toStringAsFixed(0)}% завершено",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text("$label: ", style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, CampaignDto campaign) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBgSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Удалить рассылку?", style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text("Вы уверены, что хотите удалить «${campaign.title}»?", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Отмена", style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(campaignsProvider.notifier).delete(campaign.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Удалить", style: TextStyle(color: Colors.white)),
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
