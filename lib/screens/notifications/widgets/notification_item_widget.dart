import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/notifications/helpers/app_notifications.dart';
import 'package:partiu/screens/notifications/helpers/notification_text_sanitizer.dart';
import 'package:partiu/screens/notifications/helpers/notification_message_translator.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Widget simples de notificação - Padrão Chatter
class NotificationItemWidget extends StatelessWidget {
  const NotificationItemWidget({
    required this.notification,
    required this.isVipEffective,
    required this.i18n,
    required this.index,
    required this.totalCount,
    super.key,
    this.onTap,
  });
  
  final DocumentSnapshot<Map<String, dynamic>> notification;
  final bool isVipEffective;
  final AppLocalizations i18n;
  final int index;
  final int totalCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final data = notification.data() ?? {};
    final senderId = (data[N_SENDER_ID] as String?) ?? '';
    final senderName = (data[N_SENDER_FULLNAME] as String?) ?? '';
    final nType = NotificationMessageTranslator.extractType(data) ?? '';
    final isUnread = !((data[N_READ] as bool?) ?? false);
    
    // Extrair parâmetros e traduzir mensagem
    final params = NotificationMessageTranslator.extractParams(data);
    final deepLink = params?['deepLink'] as String?;
    
    final translatedMessage = NotificationMessageTranslator.translate(
      i18n: i18n,
      type: nType,
      senderName: senderName,
      params: params,
    );
    
    return Column(
      children: [
        InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            
            if (onTap != null) onTap!();
            
            final appNotifications = AppNotifications();
            appNotifications.onNotificationClick(
              context,
              nType: nType,
              nSenderId: senderId,
              nRelatedId: (data['n_related_id'] as String?) ?? 
                         (data['relatedId'] as String?),
              deepLink: deepLink,
              screen: data['screen'] as String?,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Avatar
                StableAvatar(
                  userId: senderId,
                  size: 42,
                  enableNavigation: false,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReactiveUserNameWithBadge(
                        userId: senderId,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        NotificationTextSanitizer.clean(translatedMessage),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          letterSpacing: -0.2,
                          fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                          color: isUnread
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
