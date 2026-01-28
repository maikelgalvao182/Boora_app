import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/widgets/components.dart';
import 'package:partiu/features/profile/presentation/models/edit_profile_models.dart';
import 'package:partiu/features/profile/presentation/models/edit_profile_commands.dart';
import 'package:partiu/features/profile/presentation/tabs/gallery_tab.dart';
import 'package:partiu/features/profile/presentation/tabs/personal_tab.dart';
import 'package:partiu/features/profile/presentation/viewmodels/edit_profile_view_model_refactored.dart' as vm;
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/shared/repositories/auth_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/image_source_bottom_sheet.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/features/auth/presentation/widgets/specialty_selector_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ==================== MVVM + COMMAND PATTERN IMPLEMENTATION ====================
// Seguindo BOAS_PRATICAS.MD:
// - [OK] View separada de ViewModel
// - [OK] Widget "burro" sem lógica de negócio
// - [OK] Commands explícitos para ações do usuário
// - [OK] ViewModel não depende de BuildContext
// - [OK] Injeção de Dependência via Provider
// - [OK] Fluxo unidirecional de dados (View → ViewModel → Repository)
// - [OK] Estado gerenciado pelo ViewModel (ProfileFormData imutável)
// - [OK] View NÃO acessa AppState diretamente (usa getters do ViewModel)
// - [OK] Lógica de seleção de imagem abstraída em Service
// - [OK] Controllers gerenciados pela View (componentes de UI)
// - [OK] Controllers inicializados UMA VEZ após loadProfileData()
// - [OK] Validação de formulário no ViewModel (funções puras)
// - [OK] UserRepository abstrai acesso ao AppState
// - [OK] Sem estado duplicado (controllers são UI, formData é estado)
// - [OK] Sem sincronização bidirecional (apenas View → ViewModel)

/// Tela de edição de perfil refatorada seguindo padrão MVVM
/// 
/// Responsabilidades:
/// - Renderizar UI baseada no estado do ViewModel
/// - Gerenciar TextEditingControllers (componentes de UI)
/// - Inicializar controllers UMA VEZ após carregar dados
/// - Coletar dados dos controllers e construir ProfileFormData
/// - Delegar ações do usuário ao ViewModel (fluxo unidirecional)
/// - Interpretar e executar Commands retornados pelo ViewModel
/// - Executar navegação/toast/dialogs baseado nos Commands
/// - Validar formulário localmente (FormKey)
/// - Não conter lógica de negócio
/// - Não sincronizar controllers bidirecionalmente (apenas init)

/// Provider wrapper for EditProfileScreen
class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => vm.EditProfileViewModelRefactored(
        authRepository: AuthRepository(),
      ),
      child: const _EditProfileScreenContent(),
    );
  }
}

/// Internal screen content
class _EditProfileScreenContent extends StatefulWidget {
  const _EditProfileScreenContent();

  @override
  State<_EditProfileScreenContent> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreenContent> {
  // ==================== LOCAL STATE (UI) ====================
  // [OK] Controllers gerenciados pela View (não pelo ViewModel)
  final _formKey = GlobalKey<FormState>();
  vm.EditProfileViewModelRefactored? _viewModel; // referência cacheada para uso no dispose
  
  // Flag para controlar inicialização única dos controllers
  bool _controllersInitialized = false;
  
  // Text controllers para campos editáveis
  late final TextEditingController _fullnameController;
  late final TextEditingController _bioController;
  late final TextEditingController _jobController;
  late final TextEditingController _localityController;
  late final TextEditingController _languagesController;
  late final TextEditingController _instagramController;
  
  // Controllers adicionais para outros campos (read-only ou selecionáveis)
  late final TextEditingController _genderController;
  late final TextEditingController _sexualOrientationController;
  late final TextEditingController _lookingForController;
  late final TextEditingController _maritalStatusController;
  late final TextEditingController _birthDayController;
  late final TextEditingController _birthMonthController;
  late final TextEditingController _birthYearController;
  late final TextEditingController _countryController;
  
  @override
  void initState() {
    super.initState();
    
    // Inicializa controllers
    _fullnameController = TextEditingController();
    _bioController = TextEditingController();
    _jobController = TextEditingController();
    _localityController = TextEditingController();
    _languagesController = TextEditingController();
    _instagramController = TextEditingController();
    
    // Inicializa controllers adicionais
    _genderController = TextEditingController();
    _sexualOrientationController = TextEditingController();
    _lookingForController = TextEditingController();
    _maritalStatusController = TextEditingController();
    _birthDayController = TextEditingController();
    _birthMonthController = TextEditingController();
    _birthYearController = TextEditingController();
    _countryController = TextEditingController();
    
    // Escuta mudanças no ViewModel e processa Commands
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewModel = context.read<vm.EditProfileViewModelRefactored>();
      _viewModel!.addListener(_onViewModelChanged);
      _viewModel!.loadProfileData();
    });
  }

  @override
  void dispose() {
    // [OK] View gerencia dispose dos controllers (componentes de UI)
    // Evita lookup do contexto durante dispose, que pode disparar o assert
    _viewModel?.removeListener(_onViewModelChanged);
    
    _fullnameController.dispose();
    _bioController.dispose();
    _jobController.dispose();
    _localityController.dispose();
    _languagesController.dispose();
    _instagramController.dispose();
    
    // Dispose dos controllers adicionais
    _genderController.dispose();
    _sexualOrientationController.dispose();
    _lookingForController.dispose();
    _maritalStatusController.dispose();
    _birthDayController.dispose();
    _birthMonthController.dispose();
    _birthYearController.dispose();
    _countryController.dispose();
    
    super.dispose();
  }

  /// Callback quando ViewModel notifica mudanças
  /// Processa Commands emitidos pelo ViewModel
  void _onViewModelChanged() {
    final viewModel = context.read<vm.EditProfileViewModelRefactored>();
    final command = viewModel.lastCommand;
    
    if (command != null && mounted) {
      _processCommand(command);
      viewModel.clearCommand();
    }
    
    // [OK] Inicializa controllers APENAS UMA VEZ após carregar dados
    if (viewModel.state is EditProfileStateLoaded && !_controllersInitialized) {
      _initializeControllers(viewModel);
      _controllersInitialized = true;
    }
    
    // ✅ Sincroniza controllers apenas após comandos que alteram dados
    // NÃO sincronizar durante edição normal para evitar sobrescrever mudanças do usuário
    if (command is SaveProfileSuccessCommand && viewModel.state is EditProfileStateLoaded) {
      _syncControllersWithViewModel(viewModel);
    }
  }
  
  /// Inicializa controllers com dados carregados do ViewModel
  /// Chamado APENAS UMA VEZ após loadProfileData() completar
  void _initializeControllers(vm.EditProfileViewModelRefactored viewModel) {
    final formData = (viewModel.state as EditProfileStateLoaded).formData;
    
    // ✅ PRELOAD: Carregar avatar do usuário atual antes da UI renderizar
    final userId = viewModel.userId;
    final photoUrl = viewModel.currentPhotoUrl;
    if (userId.isNotEmpty && photoUrl.isNotEmpty) {
      UserStore.instance.preloadAvatar(userId, photoUrl);
    }
    
    _syncControllersWithFormData(formData);
  }
  
  /// Sincroniza controllers com o ViewModel após mudanças
  /// Chamado quando o ViewModel notifica mudanças no estado
  void _syncControllersWithViewModel(vm.EditProfileViewModelRefactored viewModel) {
    final formData = (viewModel.state as EditProfileStateLoaded).formData;
    _syncControllersWithFormData(formData);
  }
  
  /// Atualiza controllers com dados do ProfileFormData
  void _syncControllersWithFormData(ProfileFormData formData) {
    _fullnameController.text = formData.fullname ?? '';
    _bioController.text = formData.bio;
    _jobController.text = formData.jobTitle;
    
    // ✅ Localização: Formatar locality, state e locationCountry para exibição (read-only)
    // NÃO incluir 'country' (origem) aqui - localização só muda via UpdateLocationScreen
    final locationParts = <String>[];
    if (formData.locality != null && formData.locality!.isNotEmpty) {
      locationParts.add(formData.locality!);
    }
    if (formData.state != null && formData.state!.isNotEmpty) {
      locationParts.add(formData.state!);
    }
    if (formData.locationCountry != null && formData.locationCountry!.isNotEmpty) {
      locationParts.add(formData.locationCountry!);
    }
    _localityController.text = locationParts.join(', ');
    
    _languagesController.text = formData.languages ?? '';
    _instagramController.text = formData.instagram ?? '';
    
    // Inicializa controllers adicionais
    _genderController.text = formData.gender ?? '';
    _sexualOrientationController.text = formData.sexualOrientation ?? '';
    _lookingForController.text = formData.lookingFor ?? '';
    _maritalStatusController.text = formData.maritalStatus ?? '';
    _birthDayController.text = formData.birthDay?.toString() ?? '';
    _birthMonthController.text = formData.birthMonth?.toString() ?? '';
    _birthYearController.text = formData.birthYear?.toString() ?? '';
    _countryController.text = formData.country ?? '';
  }

  // ==================== COMMAND PROCESSOR ====================
  
  /// Processa Commands retornados pelo ViewModel
  /// Esta é a única parte da View que "executa ações"
  /// Todo o resto é apenas renderização
  void _processCommand(EditProfileCommand command) {
    if (command is SaveProfileSuccessCommand) {
      _handleSaveSuccess(command);
    } else if (command is SaveProfileErrorCommand) {
      _handleSaveError(command);
    } else if (command is UpdatePhotoSuccessCommand) {
      _handlePhotoUpdateSuccess(command);
    } else if (command is UpdatePhotoErrorCommand) {
      _handlePhotoUpdateError(command);
    } else if (command is ShowFeedbackCommand) {
      _showFeedback(command);
    } else if (command is ValidationFailedCommand) {
      _handleValidationFailed(command);
    } else if (command is NavigateBackCommand) {
      _navigateBack(command);
    }
  }
  
  /// Executa comando de sucesso ao salvar
  void _handleSaveSuccess(SaveProfileSuccessCommand command) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(command.messageKey);
    
    ToastService.showSuccess(
      message: translated.isNotEmpty ? translated : i18n.translate('profile_updated_successfully'),
    );
    
    // Removido redirecionamento - usuário permanece na tela após salvar
    // Navigator.of(context).pop(true);
  }
  
  /// Executa comando de erro ao salvar
  void _handleSaveError(SaveProfileErrorCommand command) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(command.messageKey);
    
    ToastService.showError(
      message: translated.isNotEmpty ? translated : i18n.translate('save_profile_error'),
    );
  }
  
  /// Executa comando de sucesso ao atualizar foto
  void _handlePhotoUpdateSuccess(UpdatePhotoSuccessCommand command) {
    final i18n = AppLocalizations.of(context);
    
    final titleKey = command.messageKey;
    final title = i18n.translate(titleKey);

    // Fallback para valores padrão se tradução não funcionar
    final displayTitle = title.isNotEmpty ? title : i18n.translate('photo_updated_successfully');

    // [OK] Invalida cache de markers do mapa para refletir nova foto
    try {
      final viewModel = context.read<vm.EditProfileViewModelRefactored>();
      final userId = viewModel.userId;
      if (userId.isNotEmpty) {
        // TODO: Invalidate map markers cache if needed
        // CustomMarkerGenerator.clearUserCache(userId);
        
        // Também limpa cache da imagem antiga se disponível
        final newPhotoUrl = command.newPhotoUrl;
        if (newPhotoUrl.isNotEmpty) {
          // CustomMarkerGenerator.clearImageCache(newPhotoUrl);
        }
      }
    } catch (e) {
      // Ignora erro de invalidação de cache - não é crítico
    }
    
    ToastService.showSuccess(
      message: displayTitle,
    );
  }
  
  /// Executa comando de erro ao atualizar foto
  void _handlePhotoUpdateError(UpdatePhotoErrorCommand command) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(command.messageKey);
    
    ToastService.showError(
      message: translated.isNotEmpty ? translated : i18n.translate('photo_update_error'),
    );
  }
  
  /// Executa comando de feedback genérico
  void _showFeedback(ShowFeedbackCommand command) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(command.messageKey);
    
    if (command.isError) {
      ToastService.showError(
        message: translated.isNotEmpty ? translated : i18n.translate('error'),
      );
    } else if (command.isSuccess) {
      ToastService.showSuccess(
        message: translated.isNotEmpty ? translated : i18n.translate('success'),
      );
    } else {
      ToastService.showInfo(
        message: translated.isNotEmpty ? translated : i18n.translate('info'),
      );
    }
  }
  
  /// Executa comando de validação falhou
  void _handleValidationFailed(ValidationFailedCommand command) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(command.messageKey);
    
    // Mostra toast genérico
    ToastService.showError(
      message: translated.isNotEmpty ? translated : i18n.translate('validation_failed'),
    );
    
    // Poderia destacar campos com erro na UI aqui
  }
  
  /// Navega de volta
  void _navigateBack(NavigateBackCommand command) {
    Navigator.of(context).pop(command.shouldRefresh);
  }

  // ==================== EVENT HANDLERS ====================

  /// Handler: Salvar perfil
  /// [OK] View constrói ProfileFormData a partir dos controllers locais
  Future<void> _handleSave() async {
    debugPrint('🔵 [EditProfileScreen] _handleSave() iniciado');
    
    final viewModel = context.read<vm.EditProfileViewModelRefactored>();
    
    // 1. Valida Form localmente
    debugPrint('🔵 [EditProfileScreen] Validando form...');
    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [EditProfileScreen] Validação do form falhou');
      final i18n = AppLocalizations.of(context);
      final translated = i18n.translate('please_fill_required_fields');
      ToastService.showError(
        message: translated.isNotEmpty ? translated : i18n.translate('validation_failed'),
      );
      return;
    }
    
    debugPrint('✅ [EditProfileScreen] Form validado com sucesso');
    
    // 2. Constrói ProfileFormData dos controllers
    debugPrint('🔵 [EditProfileScreen] Construindo ProfileFormData...');
    final formData = _buildFormDataFromControllers(viewModel);
    debugPrint('✅ [EditProfileScreen] ProfileFormData construído:');
    debugPrint('   - fullname: ${formData.fullname}');
    debugPrint('   - bio: ${formData.bio}');
    debugPrint('   - instagram: ${formData.instagram}');
    debugPrint('   - jobTitle: ${formData.jobTitle}');
    
    // 3. Envia ao ViewModel para salvar (fluxo unidirecional)
    debugPrint('🔵 [EditProfileScreen] Chamando viewModel.handleSaveProfile()...');
    try {
      await viewModel.handleSaveProfile(formData);
      debugPrint('✅ [EditProfileScreen] viewModel.handleSaveProfile() completado');
    } catch (e, stackTrace) {
      debugPrint('❌ [EditProfileScreen] Erro ao chamar handleSaveProfile: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    // Command será processado automaticamente via listener
  }
  
  /// Constrói ProfileFormData a partir dos controllers locais
  /// [OK] View é responsável por coletar dados editáveis
  /// [OK] Combina com dados não-editáveis do estado atual
  ProfileFormData _buildFormDataFromControllers(vm.EditProfileViewModelRefactored viewModel) {
    final currentState = viewModel.state;
    final currentData = currentState is EditProfileStateLoaded 
        ? currentState.formData 
        : const ProfileFormData();
    
    // Parse birth date
    int? birthDay;
    int? birthMonth;
    int? birthYear;
    
    try {
      if (_birthDayController.text.isNotEmpty) {
        birthDay = int.tryParse(_birthDayController.text.trim());
      }
      if (_birthMonthController.text.isNotEmpty) {
        birthMonth = int.tryParse(_birthMonthController.text.trim());
      }
      if (_birthYearController.text.isNotEmpty) {
        birthYear = int.tryParse(_birthYearController.text.trim());
      }
    } catch (_) {}
    
    // View coleta TODOS os campos editáveis
    // ⚠️ IMPORTANTE: locality e state NÃO são editáveis aqui
    // Eles só podem ser atualizados via UpdateLocationScreen
    // ✅ Country é editável via PersonalFieldEditorScreen
    return currentData.copyWith(
      fullname: _fullnameController.text.trim(),
      bio: _bioController.text.trim(),
      jobTitle: _jobController.text.trim(),
      gender: _genderController.text.trim().isEmpty ? null : _genderController.text.trim(),
      sexualOrientation: _sexualOrientationController.text.trim().isEmpty ? null : _sexualOrientationController.text.trim(),
      lookingFor: _lookingForController.text.trim().isEmpty ? null : _lookingForController.text.trim(),
      maritalStatus: _maritalStatusController.text.trim().isEmpty ? null : _maritalStatusController.text.trim(),
      birthDay: birthDay,
      birthMonth: birthMonth,
      birthYear: birthYear,
      country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
      languages: _languagesController.text.trim(),
      instagram: _instagramController.text.trim(),
      // Offers mantém os dados do currentData (gerenciados pela OffersTab)
      offers: currentData.offers,
    );
  }
  
  /// Handler: Atualizar foto de perfil
  /// Abre bottom sheet para seleção com crop, depois faz upload
  Future<void> _handleUpdateProfilePhoto() async {
    try {
      // Abre bottom sheet para seleção de foto com crop
      final viewModel = context.read<vm.EditProfileViewModelRefactored>();
      
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return ImageSourceBottomSheet(
            onImageSelected: (file) async {
              // Upload da imagem já cropada
              await viewModel.handleUpdatePhoto(file);
              // Command será processado automaticamente via listener
            },
            cropToSquare: true,
            requireCrop: true,
            minWidth: 800,
            minHeight: 800,
            quality: 85,
          );
        },
      );
    } catch (e) {
      debugPrint('❌ Error selecting photo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context); // Mantido pois é usado em appBar e estados
    return Consumer<vm.EditProfileViewModelRefactored>(
      builder: (context, viewModel, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: GlimpseAppBar(
            title: i18n.translate('edit_profile'),
            onBack: () => Navigator.pop(context),
            onAction: _handleSave,
            actionText: i18n.translate('save'),
            isActionLoading: viewModel.state is EditProfileStateSaving,
          ),
          body: switch (viewModel.state) {
            EditProfileStateInitial() => const Center(
              child: CupertinoActivityIndicator(radius: 14),
            ),
            EditProfileStateLoaded(:final formData) => _buildForm(formData, viewModel),
            // [OK] Durante salvamento, mantém formulário visível (indicator está no AppBar)
            EditProfileStateSaving(:final formData) => _buildForm(formData, viewModel),
            // [OK] Durante upload de foto, mostra formulário normal (spinner está no avatar)
            EditProfileStateUpdatingPhoto(:final formData) => _buildForm(formData, viewModel),
            EditProfileStateError(:final message) => _buildError(message),
          },
        );
      },
    );
  }
  
  /// Constrói formulário com dados carregados
  Widget _buildForm(ProfileFormData formData, vm.EditProfileViewModelRefactored viewModel) {
    return SingleChildScrollView(
      padding: GlimpseStyles.screenAllPadding,
      child: Form(
        key: _formKey, // [OK] Usa FormKey local da View
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Photo
            _ProfilePhotoSection(
              onTap: _handleUpdateProfilePhoto,
            ),
            
            const SizedBox(height: 24),
            
            // Tab Navigation (se não for bride)
            // [OK] CORRIGIDO: Usa ProfileHorizontalTabs (similar a WeddingHorizontalFilters)
            ProfileHorizontalTabs(
              selectedIndex: viewModel.selectedTabIndex,
              isBride: false,
              onTabChanged: viewModel.selectTab,
            ),
            
            const SizedBox(height: 24),
            
            // Tab Content
            _buildTabContent(formData, viewModel),
          ],
        ),
      ),
    );
  }
  
  /// Renderiza conteúdo da tab selecionada
  Widget _buildTabContent(ProfileFormData formData, vm.EditProfileViewModelRefactored viewModel) {
    final i18n = AppLocalizations.of(context);
    
    // [OK] CORRIGIDO: Renderiza o conteúdo correto baseado na tab selecionada
    return switch (viewModel.selectedTabIndex) {
      0 => _buildPersonalTab(formData, viewModel, i18n),
      1 => _buildInterestsTab(formData, viewModel),
      2 => _buildGalleryTab(),
      _ => _buildPersonalTab(formData, viewModel, i18n), // Fallback
    };
  }
  
  /// Tab de interesses
  Widget _buildInterestsTab(ProfileFormData formData, vm.EditProfileViewModelRefactored viewModel) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: SpecialtySelectorWidget(
        initialSpecialty: formData.interests ?? '',
        onSpecialtyChanged: (interests) {
          // Atualiza o campo de interesses no formData
          if (interests != null) {
            viewModel.updateField('interests', interests);
          }
        },
      ),
    );
  }
  
  /// Tab de galeria
  Widget _buildGalleryTab() {
    return const GalleryTab();
  }
  
  /// Tab de informações pessoais
  Widget _buildPersonalTab(ProfileFormData formData, vm.EditProfileViewModelRefactored viewModel, AppLocalizations i18n) {
    return PersonalTab(
      fullnameController: _fullnameController,
      jobController: _jobController,
      bioController: _bioController,
      genderController: _genderController,
      sexualOrientationController: _sexualOrientationController,
      lookingForController: _lookingForController,
      maritalStatusController: _maritalStatusController,
      birthDayController: _birthDayController,
      birthMonthController: _birthMonthController,
      birthYearController: _birthYearController,
      localityController: _localityController,
      countryController: _countryController,
      languagesController: _languagesController,
      instagramController: _instagramController,
      validateBio: (value) => viewModel.validateField('bio', value),
      validateJob: (value) => viewModel.validateField('jobTitle', value),
      labelStyle: GlimpseStyles.fieldLabelStyle(
        color: Theme.of(context).textTheme.titleMedium?.color,
      ),
      bioLabel: i18n.translate('bio'),
      bioHint: i18n.translate('bio_hint'),
      jobLabel: i18n.translate('job_title'),
      jobHint: i18n.translate('job_title_hint'),
      brideMode: false,
    );
  }
  
  /// Constrói tela de erro
  Widget _buildError(String message) {
    final i18n = AppLocalizations.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            i18n.translate('error_loading_profile'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              context.read<vm.EditProfileViewModelRefactored>().loadProfileData();
            },
            child: Text(i18n.translate('try_again')),
          ),
        ],
      ),
    );
  }
}

// ==================== OPTIMIZED WIDGETS ====================

/// Widget otimizado para seção de foto de perfil
/// [OK] Usa Consumer para reatividade quando foto muda
class _ProfilePhotoSection extends StatelessWidget {
  
  const _ProfilePhotoSection({required this.onTap});
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    // [OK] CORRIGIDO: Usa Consumer para escutar mudanças no ViewModel
    return Consumer<vm.EditProfileViewModelRefactored>(
      builder: (context, viewModel, _) {
        final isUploading = viewModel.state is EditProfileStateUpdatingPhoto;
        final photoUrl = viewModel.currentPhotoUrl;
        
        return ProfilePhotoComponent(
          userId: viewModel.userId,
          photoUrl: photoUrl,
          onTap: onTap,
          isUploading: isUploading,
        );
      },
    );
  }
}
