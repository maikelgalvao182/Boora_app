import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/api/conversations_api.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/chat_service.dart';
import 'package:partiu/features/conversations/models/conversation_item.dart';
import 'package:partiu/features/conversations/services/conversation_state_service.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/widgets/conversations_list.dart';
import 'package:partiu/features/conversations/widgets/conversation_tile.dart';
// REMOVIDO: import 'package:partiu/widgets/platform_pull_to_refresh.dart'; - pull-to-refresh removido
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/skeletons/conversation_list_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Widget responsável por renderizar o stream de conversas
class ConversationStreamWidget extends StatelessWidget {

  const ConversationStreamWidget({
    required this.isVipEffective, required this.onTap, required this.stateService, super.key,
  });
  final bool isVipEffective;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>>?, Map<String, dynamic>) onTap;
  final ConversationStateService stateService;
  
  // Singleton ChatService para time-ago reativo
  ChatService get _chatService => ChatService();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ConversationsViewModel>();
    final wsItems = viewModel.filteredWsConversations;

    // Mostra skeleton apenas se não recebeu o primeiro snapshot ainda
    if (!viewModel.hasReceivedFirstSnapshot) {
      return const ConversationListSkeleton();
    }

    // Se já recebeu o snapshot e a lista está vazia, mostra empty state
    if (wsItems.isEmpty) {
      return _buildEmptyState();
    }

    return _buildConversationsList(context, wsItems);
  }

  /// Renderiza estado vazio
  Widget _buildEmptyState() {
    return Builder(
      builder: (context) {
        final i18n = AppLocalizations.of(context);
        return GlimpseEmptyState.conversations(
          text: i18n.translate('no_conversations_yet'),
        );
      },
    );
  }

  /// Renderiza lista de conversas
  Widget _buildConversationsList(
    BuildContext context,
    List<ConversationItem> items,
  ) {
    return ConversationsList(
      itemCount: items.length,
      buildTile: (context, index) {
        final item = items[index];
        final isLast = index == items.length - 1;
        final data = {
          USER_ID: item.userId,
          USER_FULLNAME: item.userFullname,
          USER_PROFILE_PHOTO: item.userPhotoUrl,
          LAST_MESSAGE: item.lastMessage ?? '',
          MESSAGE_READ: item.isRead,
          TIMESTAMP: item.lastMessageAt?.millisecondsSinceEpoch,
        };

        return ConversationTile(
          key: ValueKey(item.id),
          conversationId: item.id,
          rawData: data,
          isVipEffective: isVipEffective,
          isLast: isLast,
          chatService: _chatService,
          onTap: () {
            onTap(null, data);
          },
        );
      },
      isVipEffective: isVipEffective,
      controller: context.read<ConversationsViewModel>().scrollController,
      // REMOVIDO: onRefresh - pull-to-refresh foi removido
      onEndReached: () => _handleEndReached(context),
      isLoadingMore: context.watch<ConversationsViewModel>().isLoadingMore,
      onTap: () {},
    );
  }

  /// Lida com o carregamento de mais itens
  Future<void> _handleEndReached(BuildContext context) async {
    print('🟡 [ConversationStreamWidget] _handleEndReached chamado');
    final viewModel = context.read<ConversationsViewModel>();
    
    // Verifica se já está carregando ou não há mais itens
    if (viewModel.isLoadingMore || !viewModel.hasMore) {
      print('🟡 [ConversationStreamWidget] _handleEndReached ignorado - isLoading: ${viewModel.isLoadingMore}, hasMore: ${viewModel.hasMore}');
      return;
    }
    
    print('🟡 [ConversationStreamWidget] Iniciando loadMore');
    await viewModel.loadMore(({
      required DocumentSnapshot<Map<String, dynamic>> startAfter,
      int limit = 20
    }) {
      return ConversationsApi().fetchConversationsPage(
        startAfter: startAfter,
        limit: limit,
      );
    });
  }
}
