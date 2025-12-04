import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/create_flow/activity_repository.dart';
import 'package:partiu/features/home/presentation/widgets/controllers/participants_drawer_controller.dart';
import 'package:partiu/features/home/presentation/widgets/participants/age_range_filter.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/people_picker.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';

/// Bottom sheet para seleção de participantes e privacidade da atividade
class ParticipantsDrawer extends StatefulWidget {
  const ParticipantsDrawer({super.key, this.coordinator});

  final CreateFlowCoordinator? coordinator;

  @override
  State<ParticipantsDrawer> createState() => _ParticipantsDrawerState();
}

class _ParticipantsDrawerState extends State<ParticipantsDrawer> {
  late final ParticipantsDrawerController _controller;
  late final ActivityRepository _repository;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = ParticipantsDrawerController();
    _repository = ActivityRepository();
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

  void _handleContinue() async {
    if (!_controller.canContinue || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Verificar autenticação
      final currentUser = fire_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception(AppLocalizations.of(context).translate('user_not_authenticated'));
      }

      // Salvar dados no coordinator
      if (widget.coordinator != null) {
        widget.coordinator!.setParticipants(
          minAge: _controller.minAge.round(),
          maxAge: _controller.maxAge.round(),
          privacyType: _controller.selectedPrivacyType!,
          maxParticipants: _controller.maxParticipants,
        );

        // Verificar se o draft está completo
        if (widget.coordinator!.canSave) {
          debugPrint('📦 [ParticipantsDrawer] Salvando atividade...');
          debugPrint(widget.coordinator!.summary);

          // Salvar no Firestore com o userId do Firebase Auth
          final activityId = await _repository.saveActivity(
            widget.coordinator!.draft,
            currentUser.uid,
          );

          debugPrint('✅ [ParticipantsDrawer] Atividade salva com ID: $activityId');

          if (mounted) {
            // Retornar sucesso
            Navigator.of(context).pop({
              'success': true,
              'activityId': activityId,
              ..._controller.getParticipantsData(),
            });
          }
        } else {
          debugPrint('⚠️ [ParticipantsDrawer] Draft incompleto, não pode salvar');
          if (mounted) {
            Navigator.of(context).pop(_controller.getParticipantsData());
          }
        }
      } else {
        // Sem coordinator, apenas retornar dados
        if (mounted) {
          Navigator.of(context).pop(_controller.getParticipantsData());
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [ParticipantsDrawer] Erro ao salvar: $e');
      debugPrint('Stack: $stack');
      
      if (mounted) {
        // Mostrar erro para o usuário
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('error_creating_activity').replaceAll('{error}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
        
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
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

                    // Header: Back + Título + Close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Botão voltar
                        GlimpseBackButton(
                          onTap: () => Navigator.of(context).pop(),
                        ),

                        // Título centralizado
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).translate('participants_title'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: GlimpseColors.primaryColorLight,
                            ),
                          ),
                        ),

                        // Botão fechar
                        const GlimpseCloseButton(
                          size: 32,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Filtro de idade
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AgeRangeFilter(
                  minAge: _controller.minAge,
                  maxAge: _controller.maxAge,
                  onRangeChanged: (RangeValues values) {
                    _controller.setAgeRange(values.start, values.end);
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Cards de seleção de privacidade
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: PrivacyTypeSelector(
                  selectedType: _controller.selectedPrivacyType,
                  onTypeSelected: (type) {
                    _controller.setPrivacyType(type);
                  },
                ),
              ),

              // People Picker (apenas quando Aberto está selecionado)
              AnimatedExpandable(
                isExpanded: _controller.selectedPrivacyType == PrivacyType.open,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: PeoplePicker(
                        isExpanded: _controller.isPeoplePickerExpanded,
                        selectedCount: _controller.maxParticipants,
                        onToggle: _controller.togglePeoplePickerExpanded,
                        onCountChanged: _controller.setMaxParticipants,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Botão de continuar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GlimpseButton(
                  text: _isSaving 
                    ? AppLocalizations.of(context).translate('creating_activity') 
                    : AppLocalizations.of(context).translate('continue'),
                  onPressed: _controller.canContinue && !_isSaving ? _handleContinue : null,
                ),
              ),

              // Padding bottom para safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}
