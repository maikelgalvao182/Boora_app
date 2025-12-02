import 'dart:io';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/auth/presentation/screens/signup_wizard_viewmodel.dart';
import 'package:partiu/features/auth/presentation/widgets/signup_widgets.dart';
import 'package:partiu/shared/widgets/glimpse_progress_header.dart';
import 'package:partiu/features/auth/presentation/controllers/cadastro_view_model.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/shared/models/user_model.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/core/constants/constants.dart';

/// Wizard de cadastro - Fluxo VENDOR apenas
/// 
/// 🎯 UMA ÚNICA TELA que gerencia todo o fluxo de signup
/// 🎯 Progress bar dinâmico
/// 🎯 Reutiliza editores existentes
/// 
/// FLUXO VENDOR: 10 steps
/// 1. Foto de perfil
/// 2. Informações pessoais (nome + data nascimento)
/// 3. Gênero
/// 4. Profissão
/// 5. Bio
/// 6. País
/// 7. Interesses (categorias de atividades)
/// 8. Instagram
/// 9. Origem
/// 10. Avaliação
class SignupWizardScreen extends StatefulWidget {
  const SignupWizardScreen({super.key});

  @override
  State<SignupWizardScreen> createState() => _SignupWizardScreenState();
}

class _SignupWizardScreenState extends State<SignupWizardScreen> {
  static const String _tag = 'SignupWizardScreen';
  
  late CadastroViewModel _cadastroViewModel;
  late SignupWizardViewModel _wizardViewModel;
  bool _hasInitialized = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _wizardViewModel = SignupWizardViewModel();
    
    // Adiciona listener para forçar rebuild quando o step mudar
    _wizardViewModel.addListener(_onWizardChanged);
  }
  
  void _onWizardChanged() {
    // Força rebuild quando o step mudar (para atualizar botão voltar)
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      // Obtém CadastroViewModel do ServiceLocator com DI
      final serviceLocator = DependencyProvider.of(context).serviceLocator;
      _cadastroViewModel = serviceLocator.get<CadastroViewModel>();
      
      // Adiciona listener para forçar rebuild quando os campos mudarem
      _cadastroViewModel.addListener(_onCadastroChanged);
      
      // Reseta dados do cadastro anterior
      _cadastroViewModel.resetData();
      
      // Reseta wizard para começar do zero
      _wizardViewModel.reset();
      
      // Preenche nome do OAuth IMEDIATAMENTE (síncrono)
      _preloadOAuthName();
      
      _hasInitialized = true;
      
      AppLogger.info('SignupWizard initialized - starting from first step', tag: _tag);
    }
  }
  
  /// Preenche o nome do OAuth imediatamente ao abrir a tela
  void _preloadOAuthName() {
    // Usa Future.microtask para executar imediatamente mas de forma assíncrona
    Future.microtask(() async {
      try {
        // Busca nome do OAuth
        final oauthName = await UserModel(userId: 'temp').getOAuthDisplayName();
        
        // Fallback: Firebase displayName
        var prefillName = (oauthName ?? '').trim();
        if (prefillName.isEmpty) {
          final fbName = firebase_auth.FirebaseAuth.instance.currentUser?.displayName;
          if (fbName != null && fbName.trim().isNotEmpty) {
            prefillName = fbName.trim();
          }
        }
        
        // Se tem nome, preenche IMEDIATAMENTE
        if (prefillName.isNotEmpty && mounted) {
          _cadastroViewModel.setFullName(prefillName);
          AppLogger.info('OAuth name preloaded: $prefillName', tag: _tag);
        }
      } catch (e) {
        AppLogger.error('Error preloading OAuth name: $e', tag: _tag);
      }
    });
  }
  
  void _onCadastroChanged() {
    // Força rebuild quando qualquer campo do cadastro mudar
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cadastroViewModel.removeListener(_onCadastroChanged);
    _wizardViewModel.removeListener(_onWizardChanged);
    _wizardViewModel.dispose();
    super.dispose();
  }

  /// Callback para avançar no wizard
  void _handleNext() {
    AppLogger.info(
      'handleNext called - currentStep: ${_wizardViewModel.currentStep.name}, '
      'currentIndex: ${_wizardViewModel.currentStepIndex}/${_wizardViewModel.totalSteps}, '
      'isLastStep: ${_wizardViewModel.isLastStep}',
      tag: _tag,
    );
    
    // Se é o último step antes da criação da conta
    if (_wizardViewModel.isLastStep) {
      // Mostrar loading IMEDIATAMENTE antes de iniciar criação
      setState(() => _isLoading = true);
      // Pequeno delay para garantir que o loading apareça
      Future.delayed(const Duration(milliseconds: 50), _finalizarCadastro);
    } else {
      _wizardViewModel.nextStep();
    }
  }

  /// Callback para voltar no wizard
  void _handleBack() {
    // Na primeira tela, não tem volta (botão está oculto)
    // Nas demais telas, volta para o step anterior
    if (!_wizardViewModel.isFirstStep) {
      _wizardViewModel.previousStep();
    }
  }

  /// Callback para cancelar o wizard completamente
  void _handleCancel() {
    // Fecha o wizard e volta para a tela de auth
    context.go(AppRoutes.signIn);
  }
  
  /// Valida se o campo atual está preenchido
  bool _isCurrentFieldValid() {
    final model = _cadastroViewModel;
    final step = _wizardViewModel.currentStep;
    
    switch (step) {
      case SignupWizardStep.profilePhoto:
        return model.imageFile != null;
      case SignupWizardStep.personalInfo:
        return model.fullName.trim().isNotEmpty && model.isUserOldEnough();
      case SignupWizardStep.instagram:
        return model.instagram.trim().isNotEmpty;
      case SignupWizardStep.jobTitle:
        return model.jobTitle.trim().isNotEmpty;
      case SignupWizardStep.gender:
        return model.selectedGender.trim().isNotEmpty;
      case SignupWizardStep.bio:
        return true; // Bio é opcional
      case SignupWizardStep.country:
        return model.country != null && model.country!.isNotEmpty;
      case SignupWizardStep.interests:
        return model.interests.trim().isNotEmpty;
      case SignupWizardStep.origin:
        return true; // Origem é opcional
      case SignupWizardStep.evaluation:
        return true; // Campo informativo
    }
  }

  /// Finaliza o processo de cadastro
  Future<void> _finalizarCadastro() async {
    AppLogger.info('Finalizing signup', tag: _tag);
    
    final model = _cadastroViewModel;

    // Aceita os termos automaticamente
    model.setAgreeTerms(true);
    
    // Dados de onboarding consolidados
    final onboardingData = <String, dynamic>{
      'fullName': model.fullName.trim(),
      'gender': model.selectedGender,
      'birthDay': model.userBirthDay,
      'birthMonth': model.userBirthMonth,
      'birthYear': model.userBirthYear,
      'age': model.age, // Idade calculada automaticamente
      'interests': model.interests.trim(),
      'instagram': model.instagram.trim(),
      'jobTitle': model.jobTitle.trim(),
      'bio': model.bio.trim(),
      'from': model.country,
      'originSource': model.originSource,
      'agreeTerms': model.agreeTerms,
    };

    // Loading já foi setado antes de chamar esta função
    
    model.createAccount(
      onboardingData: onboardingData,
      onSuccess: () {
        AppLogger.success('Signup completed successfully', tag: _tag);
        
        // Navega diretamente para atualização de localização usando go_router
        if (mounted) {
          context.go(AppRoutes.updateLocation);
        }
      },
      onFail: (error) {
        if (mounted) setState(() => _isLoading = false);
        AppLogger.error('Signup failed: $error', tag: _tag);
        
        final i18n = AppLocalizations.of(context);
        
        // Mostra erro em dialog simples
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              i18n.translate('registration_error'),
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              '${i18n.translate('error_creating_account')}\n\n$error',
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'OK',
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// Obtém título do step atual
  String _getStepTitle() {
    final i18n = AppLocalizations.of(context);
    final step = _wizardViewModel.currentStep;
    
    switch (step) {
      case SignupWizardStep.profilePhoto:
        return i18n.translate('add_a_profile_photo');
      case SignupWizardStep.personalInfo:
        return i18n.translate('basic_information_title');
      case SignupWizardStep.instagram:
        return i18n.translate('instagram_username');
      case SignupWizardStep.jobTitle:
        return i18n.translate('job_title');
      case SignupWizardStep.gender:
        return i18n.translate('gender');
      case SignupWizardStep.bio:
        return i18n.translate('bio');
      case SignupWizardStep.country:
        return i18n.translate('country');
      case SignupWizardStep.interests:
        return i18n.translate('select_interests');
      case SignupWizardStep.origin:
        return i18n.translate('where_did_you_hear_about_us');
      case SignupWizardStep.evaluation:
        return i18n.translate('rate_your_experience');
    }
  }
  
  /// Obtém subtítulo do step atual
  String? _getStepSubtitle() {
    final i18n = AppLocalizations.of(context);
    final step = _wizardViewModel.currentStep;
    
    switch (step) {
      case SignupWizardStep.profilePhoto:
        return i18n.translate('people_like_to_see_you');
      case SignupWizardStep.personalInfo:
        return i18n.translate('this_data_cannot_be_changed_later');
      case SignupWizardStep.instagram:
        return i18n.translate('instagram_helper');
      case SignupWizardStep.jobTitle:
        return i18n.translate('job_title_helper');
      case SignupWizardStep.gender:
        return i18n.translate('select_gender');
      case SignupWizardStep.bio:
        return i18n.translate('bio_placeholder');
      case SignupWizardStep.country:
        return i18n.translate('select_country');
      case SignupWizardStep.interests:
        return i18n.translate('select_activity_categories');
      case SignupWizardStep.origin:
        return i18n.translate('help_us_understand_how_you_found_us');
      case SignupWizardStep.evaluation:
        return i18n.translate('your_feedback_helps_us_improve');
    }
  }

  /// Verifica se o step atual é de onboarding (tela cheia)
  bool _isOnboardingStep() {
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _cadastroViewModel),
        ChangeNotifierProvider.value(value: _wizardViewModel),
      ],
      child: Consumer2<CadastroViewModel, SignupWizardViewModel>(
        builder: (context, cadastroViewModel, wizardViewModel, child) {
          // Mostra loading overlay durante criação da conta
          // if (_isLoading) {
          //   return const Scaffold(
          //     backgroundColor: Colors.white,
          //     body: Center(
          //       child: Processing(),
          //     ),
          //   );
          // }
          
          final isOnboarding = _isOnboardingStep();
          
          // Layout com status bar adaptado
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: isOnboarding ? Brightness.light : Brightness.dark,
              statusBarBrightness: isOnboarding ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: isOnboarding ? Colors.black : Colors.white,
              systemNavigationBarIconBrightness: isOnboarding ? Brightness.light : Brightness.dark,
            ),
            child: Scaffold(
              backgroundColor: isOnboarding ? Colors.black : GlimpseColors.textSubTitle,
              body: isOnboarding
                  ? _buildOnboardingLayout()
                  : _buildNormalLayout(),
            ),
          );
        },
      ),
    );
  }

  /// Layout para telas de onboarding (tela cheia com overlay)
  Widget _buildOnboardingLayout() {
    final i18n = AppLocalizations.of(context);
    final isValid = _isCurrentFieldValid();
    final isLastStep = _wizardViewModel.isLastStep;
    
    return Stack(
      children: [
        // Conteúdo de onboarding em tela cheia (sem PageView, widget direto)
        Positioned.fill(
          child: _buildCurrentStepWidget(),
        ),
        // Header transparente com progress
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: MediaQuery.of(context).padding.top + 16,
            ),
            child: GlimpseProgressHeader(
              title: '',
              whiteMode: true,
              onBackTap: _handleBack,
              onCancelTap: _handleCancel,
              onContinueTap: isValid ? _handleNext : null,
              cancelText: i18n.translate('cancel'),
              continueText: i18n.translate(isLastStep ? 'finish' : 'continue'),
              isContinueEnabled: isValid,
              isProcessing: _isLoading,
              showBackButton: !_wizardViewModel.isFirstStep,
            ),
          ),
        ),
      ],
    );
  }

  /// Constrói o widget do step atual (usado no onboarding sem PageView)
  Widget _buildCurrentStepWidget() {
    return _buildStepWidget(_wizardViewModel.currentStep);
  }

  /// Constrói o widget de um step específico
  Widget _buildStepWidget(SignupWizardStep step) {
    switch (step) {
      case SignupWizardStep.profilePhoto:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ProfilePhotoWidget(
            imageFile: _cadastroViewModel.imageFile as File?,
            onImageSelected: (file) => _cadastroViewModel.setImageFile(file),
          ),
        );
      
      case SignupWizardStep.personalInfo:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              PersonalInfoWidget(
                initialName: _cadastroViewModel.fullName,
                onNameChanged: _cadastroViewModel.setFullName,
              ),
              const SizedBox(height: 24),
              BirthDateWidget(
                initialDate: _cadastroViewModel.birthDate,
                onDateChanged: (DateTime? date) {
                  if (date != null) _cadastroViewModel.setBirthDate(date);
                },
              ),
            ],
          ),
        );
      
      case SignupWizardStep.instagram:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: InstagramWidget(
            initialInstagram: _cadastroViewModel.instagram,
            onInstagramChanged: _cadastroViewModel.setInstagram,
          ),
        );
      
      case SignupWizardStep.jobTitle:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: JobTitleWidget(
            initialJobTitle: _cadastroViewModel.jobTitle,
            onJobTitleChanged: _cadastroViewModel.setJobTitle,
          ),
        );
      
      case SignupWizardStep.gender:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: GenderSelectorWidget(
            initialGender: _cadastroViewModel.selectedGender,
            onGenderChanged: (value) => _cadastroViewModel.setGender(value ?? ''),
          ),
        );
      
      case SignupWizardStep.bio:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: BioWidget(
            initialBio: _cadastroViewModel.bio,
            onBioChanged: _cadastroViewModel.setBio,
          ),
        );
      
      case SignupWizardStep.country:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: CountrySelectorWidget(
            initialCountry: _cadastroViewModel.country,
            onCountryChanged: _cadastroViewModel.setCountry,
          ),
        );
      
      case SignupWizardStep.interests:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SpecialtySelectorWidget(
            initialSpecialty: _cadastroViewModel.interests,
            onSpecialtyChanged: (value) => _cadastroViewModel.setInterests(value ?? ''),
          ),
        );
      
      case SignupWizardStep.origin:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: OriginSelectorWidget(
            initialOrigin: _cadastroViewModel.originSource,
            onOriginChanged: (value) => _cadastroViewModel.setOriginSource(value ?? ''),
          ),
        );
      
      case SignupWizardStep.evaluation:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: AppEvaluationWidget(
            isBride: false, // Sempre vendor
            shouldAutoRequestReview: false,
          ),
        );
    }
  }

  /// Layout para telas normais (com header e botão separados)
  Widget _buildNormalLayout() {
    final i18n = AppLocalizations.of(context);
    final isValid = _isCurrentFieldValid();
    final isLastStep = _wizardViewModel.isLastStep;
    
    return SafeArea(
      bottom: true,
      child: Column(
        children: [
          // Header com botões de navegação
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: GlimpseProgressHeader(
              title: _getStepTitle(),
              subtitle: _getStepSubtitle(),
              onBackTap: _handleBack,
              onCancelTap: _handleCancel,
              onContinueTap: isValid ? _handleNext : null,
              cancelText: i18n.translate('cancel'),
              continueText: i18n.translate(isLastStep ? 'finish' : 'continue'),
              isContinueEnabled: isValid,
              isProcessing: _isLoading,
              showBackButton: !_wizardViewModel.isFirstStep,
            ),
          ),
          // Conteúdo do step atual (sem PageView, widget direto)
          Expanded(
            child: _buildCurrentStepWidget(),
          ),
        ],
      ),
    );
  }
}
