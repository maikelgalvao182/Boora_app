import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/notifications/helpers/app_notifications.dart';
import 'package:partiu/features/notifications/helpers/notification_text_sanitizer.dart';
import 'package:partiu/features/notifications/helpers/notification_message_translator.dart';
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
    final senderPhotoUrl = (data['n_sender_photo_link'] as String?) ?? '';
    final nType = NotificationMessageTranslator.extractType(data) ?? '';
    final isUnread = !((data[N_READ] as bool?) ?? false);
    final timestamp = data['timestamp'];
    
    debugPrint('🔔 [NotificationItem] Building notification:');
    debugPrint('   - senderId: $senderId');
    debugPrint('   - senderName: $senderName');
    debugPrint('   - senderPhotoUrl: $senderPhotoUrl');
    debugPrint('   - nType: $nType');
    
    // Extrair parâmetros e traduzir mensagem
    final params = NotificationMessageTranslator.extractParams(data);
    final deepLink = params?['deepLink'] as String?;
    
    // ✅ NOVO: Verificar se há title/body do template (usado pelo novo sistema de notificações)
    final templateTitle = params?['title'] as String?;
    final templateBody = params?['body'] as String?;
    
    // Para notificações de chat de evento ou atividades, extrair emoji + título
    final eventTitle = params?['eventTitle'] as String?;
    final activityTitleKey = params?['activityTitle'] as String?;
    final activityText = params?['activityText'] as String?;
    
    // Se houver activityTitle (chave de tradução), traduzir
    final activityTitle = activityTitleKey != null 
        ? i18n.translate(activityTitleKey) 
        : null;
    
    // Priorizar templateTitle (do novo sistema), depois eventTitle/activityTitle (legado)
    final displayTitle = templateTitle ?? eventTitle ?? activityTitle ?? activityText;
    final emoji = params?['emoji'] as String?;
    
    // Formatar time ago
    final timeAgo = timestamp != null 
        ? TimeAgoHelper.format(context, timestamp: timestamp)
        : '';
    
    // ✅ NOVO: Priorizar templateBody (do novo sistema), caso contrário usar tradutor legado
    final String translatedMessage;
    if (templateBody != null && templateBody.isNotEmpty) {
      translatedMessage = templateBody;
    } else {
      translatedMessage = NotificationMessageTranslator.translate(
        i18n: i18n,
        type: nType,
        senderName: senderName,
        params: params,
      );
    }
    
    // Remover prefixo "Sistema:" ou "System:" e emojis de mensagens do sistema
    var cleanedMessage = translatedMessage
        .replaceFirst(RegExp(r'^Sistema:\s*'), '')
        .replaceFirst(RegExp(r'^System:\s*'), '');
    
    // Remover parte de interesses em comum (se existir)
    cleanedMessage = cleanedMessage.replaceFirst(RegExp(r'\s*•\s*Interesses em comum:.*$'), '');
    
    // Para mensagens de evento, remover emojis comuns de celebração
    if (nType == 'event_chat_message') {
      cleanedMessage = cleanedMessage
          .replaceAll('🎉', '')
          .replaceAll('🥳', '')
          .replaceAll('✨', '')
          .replaceAll('🎊', '')
          .trim();
    }
    
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
                // Avatar - para mensagens de sistema, mostrar emoji da atividade
                if (senderId == 'system' && emoji != null)
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: GlimpseColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  )
                else
                  // Avatar normal para mensagens de usuários - redondo
                  StableAvatar(
                    userId: senderId,
                    photoUrl: senderPhotoUrl.isNotEmpty ? senderPhotoUrl : null,
                    size: 42,
                    borderRadius: BorderRadius.circular(999), // Redondo
                    enableNavigation: false,
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Debug log
                      Builder(
                        builder: (context) {
                          debugPrint('   - Rendering with photoUrl: ${senderPhotoUrl.isNotEmpty ? senderPhotoUrl : "null"}');
                          debugPrint('   - Is system message: ${senderId == "system"}');
                          return const SizedBox.shrink();
                        },
                      ),
                      // Se tiver título (eventTitle ou activityText), mostrar no topo
                      if (displayTitle != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayTitle,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (timeAgo.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                timeAgo,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: GlimpseColors.textSubTitle,
                                ),
                              ),
                            ],
                          ],
                        )
                      else
                        // Para outros tipos, mostrar nome do remetente
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
                        NotificationTextSanitizer.clean(cleanedMessage),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          letterSpacing: -0.2,
                          fontWeight: FontWeight.w600,
                          color: GlimpseColors.textSubTitle,
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
        const Divider(
          color: GlimpseColors.lightTextField,
        ),
      ],
    );
  }
}
