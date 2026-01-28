import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/state/optimistic_removal_bus.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_router.dart';
import 'package:partiu/screens/chat/controllers/chat_app_bar_controller.dart';
import 'package:partiu/screens/chat/services/application_removal_service.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/screens/chat/services/event_application_removal_service.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';
import 'package:partiu/screens/chat/widgets/chat_avatar_widget.dart';
import 'package:partiu/screens/chat/widgets/event_info_row.dart';
import 'package:partiu/screens/chat/widgets/event_name_text.dart';
import 'package:partiu/screens/chat/widgets/user_location_time_widget.dart';
import 'package:partiu/screens/chat/widgets/user_presence_status_widget.dart';
import 'package:partiu/shared/widgets/glimpse_action_menu_button.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/reactive/reactive_widgets.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/shared/widgets/safety_tips_button.dart';

class ChatAppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBarWidget({
    required this.user,
    required this.chatService,
    required this.applicationRemovalService,
    required this.onDeleteChat,
    required this.onRemoveApplicationSuccess,
    super.key,
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

  /// Handler para deletar evento (apenas criador)
  Future<void> _handleDeleteEvent(BuildContext context, ChatAppBarController controller) async {
    if (!controller.isEvent) return;
    
    final i18n = AppLocalizations.of(context);
    
    // Buscar nome do evento
    String eventName = i18n.translate('this_event');
    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(controller.eventId)
          .get();
      
      if (eventDoc.exists) {
        eventName = eventDoc.data()?['activityText'] as String? ?? eventName;
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar nome do evento: $e');
    }
    
    if (!context.mounted) return;
    
    // Mostrar dialog de confirmação
    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('delete_event'),
      message: i18n.translate('delete_event_confirmation')
          .replaceAll('{event}', eventName),
      destructiveText: i18n.translate('delete'),
      cancelText: i18n.translate('cancel'),
    );
    
    if (confirmed != true || !context.mounted) return;
    
    final progressDialog = ProgressDialog(context);
    final eventDeletionService = EventDeletionService();
    
    try {
      progressDialog.show(i18n.translate('deleting_event'));
      
      final success = await eventDeletionService.deleteEvent(controller.eventId);
      
      await progressDialog.hide();
      
      if (!context.mounted) return;
      
      if (success) {
        ToastService.showSuccess(
          message: i18n.translate('event_deleted_successfully'),
        );
        Navigator.of(context).pop();
      } else {
        ToastService.showError(
          message: i18n.translate('failed_to_delete_event'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      
      if (!context.mounted) return;
      
      ToastService.showError(
        message: i18n.translate('failed_to_delete_event'),
      );
    }
  }

  /// Handler para remover aplicação do usuário no evento
  void _handleRemoveMyApplication(BuildContext context, ChatAppBarController controller) {
    if (!controller.isEvent) return;
    final eventApplicationRemovalService = EventApplicationRemovalService();
    
    eventApplicationRemovalService.handleRemoveUserApplication(
      context: context,
      eventId: controller.eventId,
      i18n: AppLocalizations.of(context),
      progressDialog: ProgressDialog(context),
      onSuccess: () {
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
    ChatAppBarController controller,
  ) async {
    final items = <GlimpseActionMenuItem>[];
    
    // Para eventos
    if (controller.isEvent) {
      final isCreator = await controller.isEventCreator();
      
      // Sempre adiciona "Ver informações do grupo" no topo
      items.add(
        GlimpseActionMenuItem(
          label: i18n.translate('group_info'),
          icon: Icons.info_outline,
          onTap: () => context.push('${AppRoutes.groupInfo}/${controller.eventId}'),
        ),
      );
      
      if (isCreator) {
        // Criador do evento: pode deletar o evento
        items.add(
          GlimpseActionMenuItem(
            label: i18n.translate('delete_event'),
            icon: Icons.event_busy,
            onTap: () => _handleDeleteEvent(context, controller),
            isDestructive: true,
          ),
        );
      } else {
        // Participante: pode remover sua aplicação
        items.add(
          GlimpseActionMenuItem(
            label: i18n.translate('remove_my_application'),
            icon: Icons.exit_to_app,
            onTap: () => _handleRemoveMyApplication(context, controller),
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
    final controller = ChatAppBarController(userId: user.userId);
    
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
            child: GestureDetector(
              onTap: () {
                ProfileScreenRouter.navigateByUserId(
                  context,
                  userId: user.userId,
                );
              },
              child: Row(
                children: [
                  ChatAvatarWidget(
                    user: user,
                    chatService: chatService,
                    controller: controller,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildNameRow(context, controller),
                        if (controller.isEvent) ...[
                          const SizedBox(height: 4),
                          EventInfoRow(
                            user: user,
                            chatService: chatService,
                            controller: controller,
                          ),
                        ] else ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: UserLocationTimeWidget(
                                  user: user,
                                  chatService: chatService,
                                  showTime: false,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildMenuButton(context, i18n, controller),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói linha com nome e status
  Widget _buildNameRow(BuildContext context, ChatAppBarController controller) {
    return Row(
      children: [
        if (controller.isEvent)
          EventNameText(
            user: user,
            chatService: chatService,
            controller: controller,
          )
        else
          Flexible(
            child: ReactiveUserNameWithBadge(userId: user.userId),
          ),
      ],
    );
  }

  /// Constrói botão de menu apropriado
  Widget _buildMenuButton(
    BuildContext context,
    AppLocalizations i18n,
    ChatAppBarController controller,
  ) {
    if (controller.isEvent) {
      // Evento: ícone direto para group info + SafetyTipsButton (à esquerda)
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SafetyTipsButton(
            icon: IconsaxPlusLinear.danger,
            iconColor: Colors.black,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                IconsaxPlusLinear.arrow_right_3,
                size: 20,
                color: Colors.black,
              ),
              onPressed: () {
                context.push('${AppRoutes.groupInfo}/${controller.eventId}');
              },
            ),
          ),
        ],
      );
    }

    // Chat 1:1: apenas SafetyTipsButton
    return const SafetyTipsButton(
      icon: IconsaxPlusLinear.danger,
      iconColor: Colors.black,
      iconSize: 20,
    );
  }
}
