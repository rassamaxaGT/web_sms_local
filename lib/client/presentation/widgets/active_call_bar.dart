import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme.dart';
import '../../logic/providers.dart';

class ActiveCallBar extends ConsumerStatefulWidget {
  const ActiveCallBar({super.key});

  @override
  ConsumerState<ActiveCallBar> createState() => _ActiveCallBarState();
}

class _ActiveCallBarState extends ConsumerState<ActiveCallBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hours = minutes ~/ 60;
    if (hours > 0) {
      final remMinutes = minutes % 60;
      return '${hours.toString().padLeft(2, '0')}:${remMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(activeCallProvider);

    if (!callState.isInCall) {
      return const SizedBox.shrink();
    }

    final displayName = (callState.contactName != null &&
            callState.contactName!.trim().isNotEmpty)
        ? callState.contactName!
        : (callState.phoneNumber ?? "Вызов");

    final isRinging = callState.callStatus == 'RINGING';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.2),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing Phone Icon
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.phone_in_talk_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Contact details & status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (callState.contactName != null &&
                        callState.phoneNumber != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        callState.phoneNumber!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isRinging
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRinging ? "Входящий / Гудки..." : "Разговор в процессе",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Live Timer Counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Text(
              _formatDuration(callState.durationSeconds),
              style: const TextStyle(
                color: Color(0xFF34D399),
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Audio Output / Bluetooth Headset Indicator
          Consumer(
            builder: (context, ref, _) {
              final vol = ref.watch(deviceVolumeProvider);
              final isBt = vol.isBluetoothConnected;
              final isWired = vol.isWiredHeadsetConnected;
              final deviceName = isBt
                  ? (vol.bluetoothDeviceName.isNotEmpty ? vol.bluetoothDeviceName : "Блютуз наушники")
                  : (isWired ? "Проводная гарнитура" : "Динамик телефона");

              return Tooltip(
                message: "Аудиовыход: $deviceName",
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBt
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.2)
                        : (isWired ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isBt
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.45)
                          : (isWired ? const Color(0xFF10B981).withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.12)),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isBt
                            ? Icons.bluetooth_audio_rounded
                            : (isWired ? Icons.headphones_rounded : Icons.phone_android_rounded),
                        size: 16,
                        color: isBt
                            ? const Color(0xFF60A5FA)
                            : (isWired ? const Color(0xFF34D399) : Colors.white60),
                      ),
                      if (isBt && vol.bluetoothDeviceName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            vol.bluetoothDeviceName,
                            style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // Phone Volume Controls
          Consumer(
            builder: (context, ref, _) {
              final vol = ref.watch(deviceVolumeProvider);
              final isRingingState = callState.callStatus == 'RINGING';
              final currentVol = isRingingState ? vol.ringVolume : vol.callVolume;
              final maxVol = isRingingState ? vol.maxRingVolume : vol.maxCallVolume;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: isRingingState ? "Убавить звонок" : "Убавить громкость разговора",
                      child: IconButton(
                        icon: const Icon(Icons.volume_down_rounded, size: 16, color: Colors.white70),
                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          if (isRingingState) {
                            ref.read(deviceVolumeProvider.notifier).ringVolumeDown();
                          } else {
                            ref.read(deviceVolumeProvider.notifier).callVolumeDown();
                          }
                          SfxService.playSent();
                        },
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      "$currentVol/$maxVol",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 2),
                    Tooltip(
                      message: isRingingState ? "Прибавить звонок" : "Прибавить громкость разговора",
                      child: IconButton(
                        icon: const Icon(Icons.volume_up_rounded, size: 16, color: Colors.white70),
                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          if (isRingingState) {
                            ref.read(deviceVolumeProvider.notifier).ringVolumeUp();
                          } else {
                            ref.read(deviceVolumeProvider.notifier).callVolumeUp();
                          }
                          SfxService.playSent();
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // End Call / Hang Up Button
          ElevatedButton.icon(
            onPressed: () async {
              await ref.read(activeCallProvider.notifier).hangup();
            },
            icon: const Icon(Icons.call_end_rounded, size: 18, color: Colors.white),
            label: const Text(
              "Сбросить",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              elevation: 4,
              shadowColor: AppColors.error.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

