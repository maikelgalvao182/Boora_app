import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/create_flow/activity_repository.dart';
import 'package:partiu/features/feed/data/repositories/activity_feed_repository.dart';
import 'package:partiu/features/home/presentation/widgets/controllers/participants_drawer_controller.dart';
import 'package:partiu/features/home/presentation/widgets/participants/age_range_filter.dart';
import 'package:partiu/features/home/presentation/widgets/participants/gender_picker_widget.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';
import 'package:partiu/shared/widgets/navigation_buttons.dart';
import 'package:partiu/core/config/dependency_provider.dart';

/// Bottom sheet para seleção de participantes e privacidade da atividade
class ParticipantsDrawer extends StatefulWidget {
  const ParticipantsDrawer({
    super.key,
    this.coordinator,
    this.editMode = false,
    this.initialMinAge,
    this.initialMaxAge,
    this.initialPrivacyType,
    this.initialGender,
  });

  final CreateFlowCoordinator? coordinator;
  final bool editMode;
  final int? initialMinAge;
  final int? initialMaxAge;
  final PrivacyType? initialPrivacyType;
  final String? initialGender;

  @override
  State<ParticipantsDrawer> createState() => _ParticipantsDrawerState();
}

class _ParticipantsDrawerState extends State<ParticipantsDrawer> {
  late final ParticipantsDrawerController _controller;
  late final ActivityRepository _repository;
  late final ActivityFeedRepository _feedRepository;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = ParticipantsDrawerController();
    // ✅ SEMPRE obter ActivityRepository via DI (com todas as 4 camadas de notificações)
    _repository = ServiceLocator().get<ActivityRepository>();
    _feedRepository = ActivityFeedRepository();
    _controller.addListener(_onControllerChanged);
    
    // Se editMode, inicializar com valores existentes
    if (widget.editMode) {
      if (widget.initialMinAge != null && widget.initialMaxAge != null) {
        _controller.setAgeRange(
          widget.initialMinAge!.toDouble(),
          widget.initialMaxAge!.toDouble(),
        );
      }
      if (widget.initialPrivacyType != null) {
        _controller.setPrivacyType(widget.initialPrivacyType!);
      }
      if (widget.initialGender != null) {
        _controller.setGender(widget.initialGender!);
      }
    }
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

    // Se estiver em modo de edição, apenas retornar o valor
    if (widget.editMode) {
      Navigator.of(context).pop(_controller.getParticipantsData());
      return;
    }

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
        // Obter dados do controller (já contém a lógica correta de gender)
        final data = _controller.getParticipantsData();
        
        // Mapear PrivacyType UI enum para string 'open'/'private' apenas para o coordinator
        // Se specificGender, é 'open' no backend
        PrivacyType effectivePrivacyType = PrivacyType.open;
        if (data['privacyType'] == PrivacyType.private) {
          effectivePrivacyType = PrivacyType.private;
        }

        widget.coordinator!.setParticipants(
          minAge: data['minAge'],
          maxAge: data['maxAge'],
          privacyType: effectivePrivacyType,
          maxParticipants: null,
          gender: data['gender'],
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
          
          // ✅ Criar item no feed do usuário (dados congelados)
          await _createFeedItem(
            eventId: activityId,
            userId: currentUser.uid,
            draft: widget.coordinator!.draft,
          );
          
          // ✅ Injetar evento no ViewModel ANTES de fechar
          // Isso garante que o marker apareça no mapa instantaneamente (sem esperar Firestore listener)
          // permitindo navegação suave assim que os drawers fecharem.
          await widget.coordinator!.loadDraftEventIntoViewModel(activityId);
          
          // Debug visual
          debugPrint('🚀 [ParticipantsDrawer] Evento injetado e pronto para navegação: $activityId');

          // ✅ Pequeno delay aguardando mapa ficar pronto (evita navegação sem marker)
          await _waitForMapReady();

          // ✅ NÃO chamar navigateToEvent aqui! 
          // O problema é que os drawers ainda estão na pilha de navegação,
          // então se navegarmos agora, o EventCard abre "embaixo" do LocationPicker.
          // A navegação será feita pelo DiscoverTab após todos os drawers fecharem.

          if (mounted) {
            // Retornar sucesso com activityId para que o DiscoverTab navegue após fechar tudo
            Navigator.of(context).pop({
              'success': true,
              'activityId': activityId,
              'navigateToEvent': true, // Flag para DiscoverTab saber que deve navegar
              ..._controller.getParticipantsData(),
            });
          }
        } else {
          // Sem coordinator, apenas retornar dados
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
      if (mounted) {
        // Mostrar erro para o usuário
        final i18n = AppLocalizations.of(context);
        ToastService.showError(
          message: i18n.translate('error_creating_activity').replaceAll('{error}', e.toString()),
        );
        
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Cria um item no feed do usuário quando o evento é criado
  /// 
  /// Os dados são "congelados" no momento da criação para que o feed
  /// mostre o estado original do evento, mesmo se ele for editado depois.
  Future<void> _createFeedItem({
    required String eventId,
    required String userId,
    required dynamic draft,
  }) async {
    debugPrint('📰 [ParticipantsDrawer] Iniciando criação de FeedItem...');
    debugPrint('   eventId: $eventId');
    debugPrint('   userId: $userId');
    
    try {
      // Obter dados do usuário atual
      final currentUserData = AppState.currentUser.value;
      final userFullName = currentUserData?.fullName ?? 'Usuário';
      final userPhotoUrl = currentUserData?.photoUrl;
      
      debugPrint('   userFullName: $userFullName');

      // Extrair dados do draft (congelados)
      final activityText = draft.activityText ?? '';
      final emoji = draft.emoji ?? '🎉';
      final locationName = draft.location?.name ?? 
                          draft.location?.formattedAddress ?? 
                          'Local';
      
      debugPrint('   activityText: $activityText');
      debugPrint('   emoji: $emoji');
      debugPrint('   locationName: $locationName');
      
      // Data do evento (usar selectedTime se disponível, senão selectedDate)
      final eventDate = draft.selectedTime ?? draft.selectedDate ?? DateTime.now();
      debugPrint('   eventDate: $eventDate');

      debugPrint('📰 [ParticipantsDrawer] Chamando _feedRepository.createFeedItem...');
      
      await _feedRepository.createFeedItem(
        eventId: eventId,
        userId: userId,
        userFullName: userFullName,
        activityText: activityText,
        emoji: emoji,
        locationName: locationName,
        eventDate: eventDate,
        userPhotoUrl: userPhotoUrl,
      );

      debugPrint('✅ [ParticipantsDrawer] FeedItem criado para evento $eventId');
    } catch (e, stack) {
      // Não bloquear criação do evento se o feed falhar
      debugPrint('⚠️ [ParticipantsDrawer] Erro ao criar FeedItem (não crítico): $e');
      debugPrint('   Stack: $stack');
    }
  }

  Future<void> _waitForMapReady({Duration timeout = const Duration(milliseconds: 1200)}) async {
    final mapViewModel = widget.coordinator?.mapViewModel;
    if (mapViewModel == null) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }

    if (mapViewModel.mapReady) return;

    final start = DateTime.now();
    while (!mapViewModel.mapReady) {
      if (DateTime.now().difference(start) >= timeout) break;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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

                    // Header: Título + Close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Título alinhado à esquerda
                        Text(
                          AppLocalizations.of(context).translate('participants_title'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: GlimpseColors.primaryColorLight,
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

              // Conteúdo Scrollável (Filtro IDADE + Privacidade/Gênero)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
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
        
                      // Cards de seleção de privacidade e gênero
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: PrivacyTypeSelector(
                          selectedType: _controller.selectedPrivacyType,
                          onTypeSelected: (type) {
                            _controller.setPrivacyType(type);
                          },
                          genderPicker: AnimatedExpandable(
                            isExpanded: _controller.selectedPrivacyType == PrivacyType.specificGender,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 4),
                              child: GenderPickerWidget(
                                selectedGender: _controller.selectedGender,
                                onGenderChanged: (gender) => _controller.setGender(gender),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Botões de navegação (fixos na base)
              NavigationButtons(
                onBack: () => Navigator.of(context).pop(),
                onContinue: _handleContinue,
                canContinue: _controller.canContinue && !_isSaving,
                isLoading: _isSaving,
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
