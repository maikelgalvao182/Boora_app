import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/services/application_removal_service.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/widgets/user_presence_status_widget.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/state/optimistic_removal_bus.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_router.dart';
import 'package:partiu/shared/widgets/glimpse_action_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/reactive/reactive_widgets.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class ChatAppBarWidget extends StatelessWidget implements PreferredSizeWidget {

  const ChatAppBarWidget({
    required this.user, required this.chatService, required this.applicationRemovalService, required this.onDeleteChat, required this.onRemoveApplicationSuccess, super.key,
  this.optimisticIsVerified,
  });
  final User user;
  final ChatService chatService;
  final ApplicationRemovalService applicationRemovalService;
  final VoidCallback onDeleteChat;
  final VoidCallback onRemoveApplicationSuccess;
  final bool? optimisticIsVerified;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  // Removed verification helper (now handled by LiveVerifiedName)

  // Temporarily disabled - uncomment when needed
  // void _makeVideoCall(BuildContext context) async {
  //   // Check user vip status
  //   if (VipAccessHelper.isVip()) {
  //     // Make video call
  //     await CallHelper.makeCall(
  //       context,
  //       userReceiver: user,
  //       callType: 'video'
  //     );
  //   } else {
  //     /// Show VIP dialog
  //     showDialog(
  //         context: context,
  //         builder: (context) => const VipDialog());
  //   }
  // }

  // Temporarily disabled - uncomment when needed
  // void _makeVoiceCall(BuildContext context) async {
  //   // Check user vip status
  //   if (VipAccessHelper.isVip()) {
  //     // Make voice call
  //     await CallHelper.makeCall(
  //       context,
  //       userReceiver: user,
  //       callType: 'voice'
  //     );
  //   } else {
  //     /// Show VIP dialog
  //     showDialog(
  //         context: context,
  //         builder: (context) => const VipDialog());
  //   }
  // }

  void _handleRemoveApplication(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    
    // Optimistically hide conversations for this userId immediately (instant UI)
    try {
      final viewModel = context.read<ConversationsViewModel?>();
      viewModel?.optimisticRemoveByUserId(user.userId);
    } catch (_) {}
    // Also broadcast globally so lists in other navigators update instantly
    ConversationRemovalBus.instance.hideUser(user.userId);
    
    applicationRemovalService.handleRemoveApplication(
      context: context,
      vendorId: user.userId,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: () {
        // Optimistically hide conversations for this userId
        try {
          final viewModel = context.read<ConversationsViewModel?>();
          viewModel?.optimisticRemoveByUserId(user.userId);
        } catch (_) {}

        // Allow external hook
        onRemoveApplicationSuccess();
        
        // Navigate back after successful removal
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  // Removed unused _formatTimeAgo helper

  Future<void> _blockProfile(BuildContext context) async {
    await chatService.blockProfile(
      context: context,
      blockedUserId: user.userId,
      i18n: AppLocalizations.of(context),
      progressDialog: ProgressDialog(context),
    );
  }

  Future<void> _unblockProfile(BuildContext context) async {
    await chatService.unblockProfile(
      context: context,
      blockedUserId: user.userId,
      i18n: AppLocalizations.of(context),
      progressDialog: ProgressDialog(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return AppBar(
      backgroundColor: GlimpseColors.bgColorLight,
      elevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: false,
      title: Row(
        children: [
          // Botão de voltar
          GlimpseBackButton(
            onTap: () => Navigator.of(context).pop(),
          ),
            
          const SizedBox(width: 12),
          
          // Informações do usuário
          Expanded(
            child: GestureDetector(
              onTap: () {
                // [OK] FIX: Navigate using ProfileScreenRouter.navigateByUserId to fetch fresh data
                // This ensures profile loads completely (not partial data from Conversation doc)
                ProfileScreenRouter.navigateByUserId(
                  context,
                  userId: user.userId,
                );
              },
              child: Row(
                children: [
                  // Avatar reativo - evento ou usuário
                  user.userId.startsWith('event_')
                      ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: chatService.getConversationSummary(user.userId),
                          builder: (context, snap) {
                            String emoji = EventEmojiAvatar.defaultEmoji;
                            String eventId = user.userId.replaceFirst('event_', '');
                            
                            if (snap.hasData && snap.data!.data() != null) {
                              final data = snap.data!.data()!;
                              emoji = data['emoji'] ?? EventEmojiAvatar.defaultEmoji;
                              eventId = data['event_id']?.toString() ?? eventId;
                            }
                            
                            return EventEmojiAvatar(
                              emoji: emoji,
                              eventId: eventId,
                              size: ConversationStyles.avatarSizeChatAppBar,
                              emojiSize: ConversationStyles.eventEmojiFontSizeChatAppBar,
                            );
                          },
                        )
                      : StableAvatar(
                          key: ValueKey(user.userId),
                          userId: user.userId,
                          size: 40,
                          enableNavigation: false,
                        ),
                  
                  const SizedBox(width: 12),
                    
                  // Nome e status do usuário
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Linha 1: Nome (activityText para eventos ou nome do usuário)
                        Row(
                          children: [
                            user.userId.startsWith('event_')
                                ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                    stream: chatService.getConversationSummary(user.userId),
                                    builder: (context, snap) {
                                      String eventName = 'Evento';
                                      if (snap.hasData && snap.data!.data() != null) {
                                        final data = snap.data!.data()!;
                                        eventName = data['activityText'] ?? 'Evento';
                                      }
                                      return ConversationStyles.buildEventNameText(
                                        name: eventName,
                                      );
                                    },
                                  )
                                : Flexible(
                                    child: ReactiveUserNameWithBadge(
                                      userId: user.userId,
                                    ),
                                  ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: UserPresenceStatusWidget(
                                userId: user.userId,
                                chatService: chatService,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Linha 2: Schedule formatado
                        if (user.userId.startsWith('event_'))
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: chatService.getConversationSummary(user.userId),
                            builder: (context, snap) {
                              String scheduleText = '';
                              if (snap.hasData && snap.data!.data() != null) {
                                final data = snap.data!.data()!;
                                final schedule = data['schedule'];
                                if (schedule != null && schedule is Map) {
                                  final date = schedule['date'];
                                  if (date != null) {
                                    DateTime? dateTime;
                                    if (date is Timestamp) {
                                      dateTime = date.toDate();
                                    } else if (date is DateTime) {
                                      dateTime = date;
                                    }
                                    
                                    if (dateTime != null) {
                                      final day = dateTime.day.toString().padLeft(2, '0');
                                      final month = dateTime.month.toString().padLeft(2, '0');
                                      final year = dateTime.year.toString().substring(2);
                                      final hour = dateTime.hour.toString().padLeft(2, '0');
                                      final minute = dateTime.minute.toString().padLeft(2, '0');
                                      scheduleText = '$day/$month/$year às $hour:$minute';
                                    }
                                  }
                                }
                              }
                              
                              if (scheduleText.isEmpty) return const SizedBox.shrink();
                              
                              return Text(
                                scheduleText,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: GlimpseColors.textSubTitle,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  
                  // Coluna direita: Menu 3 pontos e time-ago
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Menu de opções (3 pontos) - removendo paddings internos
                      GlimpseActionMenuButton(
                        iconColor: GlimpseColors.primaryColorLight,
                        padding: EdgeInsets.zero,
                        buttonSize: 24,
                        iconSize: 20,
                        items: [
                          GlimpseActionMenuItem(
                            label: i18n.translate('delete_conversation'),
                            icon: Icons.delete_outline,
                            onTap: onDeleteChat,
                            isDestructive: true,
                          ),
                          GlimpseActionMenuItem(
                            label: i18n.translate('remove_application'),
                            icon: Icons.highlight_off,
                            onTap: () => _handleRemoveApplication(context),
                            isDestructive: true,
                          ),
                          if (!chatService.isRemoteUserBlocked)
                            GlimpseActionMenuItem(
                              label: i18n.translate('Block'),
                              icon: Icons.block,
                              onTap: () => _blockProfile(context),
                            )
                          else
                            GlimpseActionMenuItem(
                              label: i18n.translate('Unblock'),
                              icon: Icons.block,
                              onTap: () => _unblockProfile(context),
                            ),
                        ],
                      ),
                      // Time-ago da última mensagem
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: chatService.getConversationSummary(user.userId),
                        builder: (context, snap) {
                          var timeAgoText = '';
                          if (snap.hasData && snap.data!.data() != null) {
                            final data = snap.data!.data()!;
                            final timestampValue = data['last_message_timestamp']
                                ?? data['last_message_at']
                                ?? data['lastMessageAt']
                                ?? data[TIMESTAMP]
                                ?? data['timestamp'];
                            
                            timeAgoText = TimeAgoHelper.format(
                              timestamp: timestampValue,
                              locale: i18n.translate('lang'),
                            );
                          }
                          if (timeAgoText.isEmpty) return const SizedBox.shrink();
                          
                          final baseStyle = ConversationStyles.subtitle(
                            color: GlimpseColors.textSubTitle,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(timeAgoText, style: baseStyle),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: const [],
    );
  }
}
