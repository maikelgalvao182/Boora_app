import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/list_card.dart';
import 'package:partiu/features/home/presentation/widgets/list_card/list_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/list_drawer/list_drawer_controller.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/features/home/presentation/widgets/list_card_shimmer.dart';

/// Drawer/Bottom sheet para exibir lista de atividades na região
class ListDrawer extends StatefulWidget {
  const ListDrawer({super.key});

  @override
  State<ListDrawer> createState() => _ListDrawerState();
}

class _ListDrawerState extends State<ListDrawer> {
  late final ListDrawerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ListDrawerController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      height: screenHeight * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle e header
              Padding(
                padding: const EdgeInsets.only(
                  top: 12,
                  left: 20,
                  right: 20,
                ),
                child: Column(
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: GlimpseColors.borderColorLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Título centralizado
                    Text(
                      i18n?.translate('activities_in_region') ?? 'Atividades na região',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Lista de atividades
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Constrói conteúdo baseado no estado do controller
  Widget _buildContent() {
    // Usuário não autenticado
    if (_controller.currentUserId == null) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: 'Usuário não autenticado',
        ),
      );
    }

    // Loading state (ambas streams carregando)
    if (_controller.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const ListCardShimmer(),
            const ListCardShimmer(),
            const ListCardShimmer(),
          ],
        ),
      );
    }

    // Empty state (terminou de carregar e não tem nada)
    if (_controller.isEmpty) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: 'Nenhuma atividade encontrada',
        ),
      );
    }

    // Content with data
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SEÇÃO: Suas atividades
            if (_controller.hasMyEvents) ...[
              _buildSectionLabel('Suas atividades'),
              const SizedBox(height: 12),
              _buildMyEventsList(),
              const SizedBox(height: 32),
            ],
            
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  /// Constrói label de seção (widget const reutilizável)
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: GlimpseColors.textSubTitle,
      ),
    );
  }

  /// Constrói lista de eventos criados pelo usuário
  Widget _buildMyEventsList() {
    return Column(
      children: _controller.myEvents.map((eventDoc) {
        return _EventCardWrapper(
          key: ValueKey(eventDoc.id),
          eventId: eventDoc.id,
        );
      }).toList(),
    );
  }
}

/// Widget wrapper para ListCard com FutureBuilder
/// Separado para evitar rebuilds desnecessários
class _EventCardWrapper extends StatelessWidget {
  const _EventCardWrapper({
    required this.eventId,
    this.distanceKm,
    super.key,
  });

  final String eventId;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final controller = ListCardController(eventId: eventId);

    return FutureBuilder(
      future: controller.load(),
      builder: (context, snapshot) {
        return ListCard(
          controller: controller,
          onTap: () {
            if (distanceKm != null) {
              debugPrint('Evento próximo clicado: $eventId (${distanceKm!.toStringAsFixed(1)} km)');
            } else {
              debugPrint('Meu evento clicado: $eventId');
            }
          },
        );
      },
    );
  }
}
