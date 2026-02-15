import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/notifications/helpers/app_notifications.dart';
import 'package:partiu/features/notifications/helpers/notification_text_sanitizer.dart';
import 'package:partiu/features/notifications/helpers/notification_message_translator.dart';
import 'package:partiu/features/notifications/models/notification_cache_item.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
    this.isLocallyRead = false,
  });
  
  final NotificationCacheItem notification;
  final bool isVipEffective;
  final AppLocalizations i18n;
  final int index;
  final int totalCount;
  final VoidCallback? onTap;
  final bool isLocallyRead;

  @override
  Widget build(BuildContext context) {
    final data = notification.data;
    final senderId = (data[N_SENDER_ID] as String?) ?? '';
    // ⚠️ ARQUITETURA: senderName/senderPhotoUrl da notificação são APENAS fallback
    // Para usuários reais, SEMPRE usar UserStore/StableAvatar que busca do Firestore
    // Isso evita inconsistências quando o backend mistura dados do Auth Provider
    final senderNameFromPayload = (data[N_SENDER_FULLNAME] as String?) ?? '';
    // IGNORADO: senderPhotoUrl - StableAvatar resolve via UserStore
    final nType = NotificationMessageTranslator.extractType(data) ?? '';
    // Se foi marcado como lido localmente, considerar como lido
    final isUnread = isLocallyRead ? false : !((data[N_READ] as bool?) ?? false);
    final timestamp = data['timestamp'];
    
    // 🔒 REGRA DE OURO: Para usuários reais, nome e avatar vêm do UserStore
    // Notificação só carrega senderId - igual WhatsApp, Instagram, TikTok
    final isSystemMessage = senderId.isEmpty || senderId == 'system';
    
    debugPrint('🔔 [NotificationItem] Building notification:');
    debugPrint('   - senderId: $senderId');
    debugPrint('   - isSystemMessage: $isSystemMessage');
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
      // Para mensagens traduzidas, usar senderName do payload como fallback
      // (ReactiveUserName será usado para exibição visual, mas traduções precisam de texto)
      translatedMessage = NotificationMessageTranslator.translate(
        i18n: i18n,
        type: nType,
        senderName: senderNameFromPayload,
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
          child: Container(
            color: isUnread ? GlimpseColors.primaryLight : Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar com badge - Stack para posicionar o dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Avatar - para mensagens de sistema, mostrar emoji se disponível
                    if (isSystemMessage && emoji != null && emoji.isNotEmpty)
                      Container(
                        width: 52.w,
                        height: 52.h,
                        decoration: BoxDecoration(
                          color: GlimpseColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: TextStyle(fontSize: 24.sp),
                          ),
                        ),
                      )
                    else
                      // 🔒 ARQUITETURA CORRETA: StableAvatar resolve avatar via UserStore
                      // NÃO passar photoUrl da notificação - isso causava inconsistências
                      // quando backend misturava dados do Auth Provider (Google) com Firestore
                      // 🔒 DEFENSIVO: Passa '' se isSystemMessage para evitar lookup inválido
                      StableAvatar(
                        userId: isSystemMessage ? '' : senderId,
                        size: 52.w,
                        borderRadius: BorderRadius.circular(999.r), // Redondo
                        enableNavigation: false,
                      ),
                    // Badge de não lido (dot vermelho)
                    if (isUnread)
                      Positioned(
                        right: 2,
                        top: 0,
                        child: Container(
                          width: 12.w,
                          height: 12.h,
                          decoration: BoxDecoration(
                            color: GlimpseColors.actionColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2.w,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Se tiver título (eventTitle ou activityText), mostrar no topo
                      if (displayTitle != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayTitle,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (timeAgo.isNotEmpty) ...[
                              SizedBox(width: 8.w),
                              Text(
                                timeAgo,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w400,
                                  color: GlimpseColors.textSubTitle,
                                ),
                              ),
                            ],
                          ],
                        )
                      else
                        // Para outros tipos, mostrar nome do remetente via UserStore
                        // 🔒 DEFENSIVO: Só renderiza se NÃO for mensagem de sistema
                        if (!isSystemMessage)
                          ReactiveUserNameWithBadge(
                            userId: senderId,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      SizedBox(height: 3.h),
                      Text(
                        NotificationTextSanitizer.clean(cleanedMessage),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14.sp,
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
        Divider(
          height: 1.h,
          thickness: 1.h,
          color: GlimpseColors.lightTextField,
        ),
      ],
    );
  }
}
