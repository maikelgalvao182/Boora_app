import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/utils/conversation_styles.dart';
import 'package:partiu/features/conversations/widgets/conversation_stream_widget.dart';
import 'package:partiu/features/conversations/widgets/conversations_header.dart';
import 'package:partiu/core/services/auth_state_service.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ConversationsViewModel movido para conversations_viewmodel.dart

/// View principal da aba de conversas
/// Agora é StatelessWidget e toda lógica está no ConversationsViewModel
class ConversationsTab extends StatelessWidget {
  const ConversationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationsViewModel>(
      builder: (context, viewModel, _) {
        final i18n = AppLocalizations.of(context);
        final isGuest = AuthStateService.instance.isGuest;

        return Scaffold(
          backgroundColor: ConversationStyles.backgroundColor(),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ConversationsHeader(),
                const SizedBox(height: ConversationStyles.headerSpacing),
                Expanded(
                  child: isGuest
                      // Guest: show Conversations UI empty state
                      ? Center(
                          child: GlimpseEmptyState.conversations(
                            text: i18n.translate('no_conversations_yet'),
                          ),
                        )
                      : ConversationStreamWidget(
                          isVipEffective: viewModel.isVipEffective,
                          onTap: (QueryDocumentSnapshot<Map<String, dynamic>>? doc, Map<String, dynamic> data) =>
                              viewModel.navigationService.handleConversationTap(
                            context: context,
                            doc: doc,
                            data: data,
                          ),
                          stateService: viewModel.stateService,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Widgets e tile movidos para a pasta widgets/
// Métodos de debug e payment removidos - devem estar em services específicos se necessário
