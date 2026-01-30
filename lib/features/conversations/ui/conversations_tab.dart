import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/conversations/widgets/conversation_stream_widget.dart';
import 'package:partiu/core/services/auth_state_service.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';
import 'package:partiu/shared/widgets/safety_tips_button.dart';
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
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final isGuest = AuthStateService.instance.isGuest;

        return Scaffold(
          backgroundColor: Colors.white, // Cor branca fixa
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlimpseTabAppBar(
                  title: i18n.translate('conversations'),
                  actions: const [
                    SafetyTipsButton(
                      icon: IconsaxPlusLinear.danger,
                      iconColor: GlimpseColors.primaryColorLight,
                      iconSize: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                          onTap: (QueryDocumentSnapshot<Map<String, dynamic>>? doc, Map<String, dynamic> data, String? conversationId) {
                              viewModel.navigationService.handleConversationTap(
                                context: context,
                                doc: doc,
                                data: data,
                                conversationId: conversationId,
                              );
                              if (conversationId != null) {
                                viewModel.markAsRead(conversationId);
                              }
                          },
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
