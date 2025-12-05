import 'package:flutter/material.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';
import 'package:partiu/app/services/localization_service.dart';

/// Tela de ações (Tab 1)
/// TODO: Implementar funcionalidade de actions
class ActionsTab extends StatelessWidget {
  const ActionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            GlimpseTabAppBar(
              title: LocalizationService.of(context).translate('actions') ?? 'Actions',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: GlimpseEmptyState.standard(
                  text: 'Nenhuma ação ainda\nImplementar funcionalidade de actions',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
