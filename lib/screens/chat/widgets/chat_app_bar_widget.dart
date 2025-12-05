import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/services/application_removal_service.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';
import 'package:partiu/screens/chat/services/event_application_removal_service.dart';
import 'package:partiu/screens/chat/widgets/user_presence_status_widget.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/features/conversations/state/optimistic_removal_bus.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_router.dart';
import 'package:partiu/shared/widgets/glimpse_action_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/reactive/reactive_widgets.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/stacked_avatars.dart';
import 'package:partiu/shared/widgets/event_emoji_avatar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:partiu/common/state/app_state.dart';

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

  // Helpers - lógica fora do build()
  bool get _isEvent => user.userId.startsWith('event_');
  String get _eventId => user.userId.replaceFirst('event_', '');

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

  /// Verifica se o usuário é o criador do evento
  Future<bool> _isEventCreator(String eventId) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) return false;

    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();
      
      if (!eventDoc.exists) return false;
      
      final createdBy = eventDoc.data()?['createdBy'] as String?;
      return createdBy == currentUserId;
    } catch (e) {
      debugPrint('❌ Erro ao verificar criador do evento: $e');
      return false;
    }
  }

  /// Handler para deletar evento (apenas criador)
  void _handleDeleteEvent(BuildContext context) {
    if (!_isEvent) return;
    
    final eventDeletionService = EventDeletionService();
    
    eventDeletionService.handleDeleteEvent(
      context: context,
      eventId: _eventId,
      i18n: AppLocalizations.of(context),
      progressDialog: ProgressDialog(context),
      onSuccess: () {
        // Navega de volta após sucesso
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  /// Handler para remover aplicação do usuário no evento
  void _handleRemoveMyApplication(BuildContext context) {
    if (!_isEvent) return;
    
    final eventApplicationRemovalService = EventApplicationRemovalService();
    
    eventApplicationRemovalService.handleRemoveUserApplication(
      context: context,
      eventId: _eventId,
      i18n: AppLocalizations.of(context),
      progressDialog: ProgressDialog(context),
      onSuccess: () {
        // Navega de volta após sucesso
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  /// Constrói itens do menu dinamicamente baseado no contexto
  Future<List<GlimpseActionMenuItem>> _buildMenuItems(
    BuildContext context,
    AppLocalizations i18n,
  ) async {
    final items = <GlimpseActionMenuItem>[];
    
    // Para eventos
    if (_isEvent) {
      final isCreator = await _isEventCreator(_eventId);
      
      // Sempre adiciona "Ver informações do grupo" no topo
      items.add(
        GlimpseActionMenuItem(
          label: i18n.translate('group_info'),
          icon: Icons.info_outline,
          onTap: () {
            // Navega para a tela de informações do grupo
            context.push('${AppRoutes.groupInfo}/$_eventId');
          },
        ),
      );
      
      if (isCreator) {
        // Criador do evento: pode deletar o evento
        items.add(
          GlimpseActionMenuItem(
            label: i18n.translate('delete_event'),
            icon: Icons.event_busy,
            onTap: () => _handleDeleteEvent(context),
            isDestructive: true,
          ),
        );
      } else {
        // Participante: pode remover sua aplicação
        items.add(
          GlimpseActionMenuItem(
            label: i18n.translate('remove_my_application'),
            icon: Icons.exit_to_app,
            onTap: () => _handleRemoveMyApplication(context),
            isDestructive: true,
          ),
        );
      }
      
      // Sempre pode deletar a conversa local
      items.add(
        GlimpseActionMenuItem(
          label: i18n.translate('delete_conversation'),
          icon: Icons.delete_outline,
          onTap: onDeleteChat,
          isDestructive: true,
        ),
      );
    } else {
      // Para conversas 1:1 (não-eventos)
      items.add(
        GlimpseActionMenuItem(
          label: i18n.translate('delete_conversation'),
          icon: Icons.delete_outline,
          onTap: onDeleteChat,
          isDestructive: true,
        ),
      );
      
      items.add(
        GlimpseActionMenuItem(
          label: i18n.translate('remove_application'),
          icon: Icons.highlight_off,
          onTap: () => _handleRemoveApplication(context),
          isDestructive: true,
        ),
      );
      
      // Bloquear/Desbloquear
      if (!chatService.isRemoteUserBlocked) {
        items.add(
          GlimpseActionMenuItem(
            label: i18n.translate('Block'),
            icon: Icons.block,
            onTap: () => _blockProfile(context),
          ),
        );
      } else {
        items.add(
          GlimpseActionMenuItem(
            label: i18n.translate('Unblock'),
            icon: Icons.block,
            onTap: () => _unblockProfile(context),
          ),
        );
      }
    }
    
    return items;
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
          GlimpseBackButton(
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ChatAppBarContent(
              user: user,
              chatService: chatService,
              isEvent: _isEvent,
              buildMenuItems: _buildMenuItems,
            ),
          ),
        ],
      ),
      actions: const [],
    );
  }
}

/// Widget de conte\u00fado do AppBar - separado para reduzir aninhamento
class _ChatAppBarContent extends StatelessWidget {
  const _ChatAppBarContent({
    required this.user,
    required this.chatService,
    required this.isEvent,
    required this.buildMenuItems,
  });

  final User user;
  final ChatService chatService;
  final bool isEvent;
  final Future<List<GlimpseActionMenuItem>> Function(BuildContext, AppLocalizations) buildMenuItems;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ProfileScreenRouter.navigateByUserId(
          context,
          userId: user.userId,
        );
      },
      child: Row(
        children: [
          _ChatAvatar(
            user: user,
            chatService: chatService,
            isEvent: isEvent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ChatUserInfo(
              user: user,
              chatService: chatService,
              isEvent: isEvent,
            ),
          ),
          _ChatMenuColumn(
            user: user,
            chatService: chatService,
            buildMenuItems: buildMenuItems,
          ),
        ],
      ),
    );
  }
}

/// Avatar do chat - evento ou usu\u00e1rio
class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.user,
    required this.chatService,
    required this.isEvent,
  });

  final User user;
  final ChatService chatService;
  final bool isEvent;

  @override
  Widget build(BuildContext context) {
    if (isEvent) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
      );
    }

    return StableAvatar(
      key: ValueKey(user.userId),
      userId: user.userId,
      size: 40,
      enableNavigation: false,
    );
  }
}

/// Informa\u00e7\u00f5es do usu\u00e1rio/evento
class _ChatUserInfo extends StatelessWidget {
  const _ChatUserInfo({
    required this.user,
    required this.chatService,
    required this.isEvent,
  });

  final User user;
  final ChatService chatService;
  final bool isEvent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChatNameRow(
          user: user,
          chatService: chatService,
          isEvent: isEvent,
        ),
        const SizedBox(height: 4),
        if (isEvent)
          _EventInfoRow(
            user: user,
            chatService: chatService,
          ),
      ],
    );
  }
}

/// Linha com nome e status
class _ChatNameRow extends StatelessWidget {
  const _ChatNameRow({
    required this.user,
    required this.chatService,
    required this.isEvent,
  });

  final User user;
  final ChatService chatService;
  final bool isEvent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isEvent)
          _EventNameText(user: user, chatService: chatService)
        else
          Flexible(
            child: ReactiveUserNameWithBadge(userId: user.userId),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: UserPresenceStatusWidget(
            userId: user.userId,
            chatService: chatService,
          ),
        ),
      ],
    );
  }
}

/// Linha com avatares empilhados, contador de membros e schedule
class _EventInfoRow extends StatelessWidget {
  const _EventInfoRow({
    required this.user,
    required this.chatService,
  });

  final User user;
  final ChatService chatService;
  
  String get _eventId => user.userId.replaceFirst('event_', '');

  String _formatSchedule(dynamic schedule) {
    if (schedule == null || schedule is! Map) return '';
    
    final date = schedule['date'];
    if (date == null) return '';

    DateTime? dateTime;
    if (date is Timestamp) {
      dateTime = date.toDate();
    } else if (date is DateTime) {
      dateTime = date;
    }
    
    if (dateTime == null) return '';
    
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString().substring(2);
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    
    return '$day/$month/$year às $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chatService.getConversationSummary(user.userId),
      builder: (context, snap) {
        String scheduleText = '';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          scheduleText = _formatSchedule(data['schedule']);
        }
        
        return Row(
          children: [
            // Avatares empilhados com contador
            StackedAvatars(
              eventId: _eventId,
              avatarSize: 18,
              maxVisible: 3,
              showMemberCount: true,
              textStyle: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: GlimpseColors.textSubTitle,
              ),
            ),
            
            // Separador e data
            if (scheduleText.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '·',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textSubTitle,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  scheduleText,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textSubTitle,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Nome do evento
class _EventNameText extends StatelessWidget {
  const _EventNameText({
    required this.user,
    required this.chatService,
  });

  final User user;
  final ChatService chatService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chatService.getConversationSummary(user.userId),
      builder: (context, snap) {
        String eventName = 'Evento';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          eventName = data['activityText'] ?? 'Evento';
        }
        return ConversationStyles.buildEventNameText(name: eventName);
      },
    );
  }
}

/// Schedule do evento formatado
class _EventScheduleText extends StatelessWidget {
  const _EventScheduleText({
    required this.user,
    required this.chatService,
  });

  final User user;
  final ChatService chatService;

  String _formatSchedule(dynamic schedule) {
    if (schedule == null || schedule is! Map) return '';
    
    final date = schedule['date'];
    if (date == null) return '';

    DateTime? dateTime;
    if (date is Timestamp) {
      dateTime = date.toDate();
    } else if (date is DateTime) {
      dateTime = date;
    }
    
    if (dateTime == null) return '';
    
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString().substring(2);
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    
    return '$day/$month/$year \u00e0s $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chatService.getConversationSummary(user.userId),
      builder: (context, snap) {
        String scheduleText = '';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          scheduleText = _formatSchedule(data['schedule']);
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
    );
  }
}

/// Coluna com menu e time-ago
class _ChatMenuColumn extends StatelessWidget {
  const _ChatMenuColumn({
    required this.user,
    required this.chatService,
    required this.buildMenuItems,
  });

  final User user;
  final ChatService chatService;
  final Future<List<GlimpseActionMenuItem>> Function(BuildContext, AppLocalizations) buildMenuItems;

  bool get _isEvent => user.userId.startsWith('event_');
  String get _eventId => user.userId.replaceFirst('event_', '');

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Para eventos: navegação direta ao clicar no ícone
        if (_isEvent)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 20,
            icon: const Icon(
              Icons.info_outline,
              color: GlimpseColors.primaryColorLight,
            ),
            onPressed: () {
              context.push('${AppRoutes.groupInfo}/$_eventId');
            },
          )
        else
          // Para conversas 1:1: menu com opções
          Builder(
            builder: (builderContext) {
              return FutureBuilder<List<GlimpseActionMenuItem>>(
                future: buildMenuItems(builderContext, i18n),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? [];
                  
                  return GlimpseActionMenuButton(
                    iconColor: GlimpseColors.primaryColorLight,
                    padding: EdgeInsets.zero,
                    buttonSize: 24,
                    iconSize: 20,
                    items: items,
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
