import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_host/shared/shared_models.dart';
import '../../../shared/theme.dart';

class MessageBubble extends StatelessWidget {
  final SmsMessageDto message;
  final String? simName;

  const MessageBubble({super.key, required this.message, this.simName});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isSent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: isMe ? AppColors.msgSent : AppColors.msgReceived,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: Border.all(
              color: isMe 
                  ? AppColors.accent.withValues(alpha: 0.25) 
                  : AppColors.border,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Linkify(
                text: message.body,
                onOpen: (link) => launchUrl(Uri.parse(link.url)),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  height: 1.35,
                ),
                linkStyle: const TextStyle(
                  color: AppColors.accentLight,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (simName != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMe 
                            ? AppColors.accent.withValues(alpha: 0.2) 
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        simName!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isMe ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _formatTime(message.date),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
