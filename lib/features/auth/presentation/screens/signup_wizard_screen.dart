import 'dart:io';
import 'package:partiu/core/utils/app_logger.dart';
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
/// FLUXO VENDOR OTIMIZADO: 3 steps essenciais
/// 1. Foto de perfil
/// 2. Informações pessoais (nome + data nascimento)
/// 3. Interesses (categorias de atividades)
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
      // 🔒 Gate de verificação de e-mail (provider=password)
      // Impede completar onboarding sem confirmar o e-mail.
      final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // Sem usuário Firebase => não há como finalizar cadastro
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.signIn);
        });
        return;
      }

      final isPasswordProvider = currentUser.providerData.any((p) => p.providerId == 'password');
      if (isPasswordProvider && currentUser.emailVerified == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(
            AppRoutes.emailVerification,
            extra: {
              'email': currentUser.email,
            },
          );
        });
        return;
      }

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
      case SignupWizardStep.bio:
        return model.bio.trim().isNotEmpty;
      case SignupWizardStep.interests:
        return model.interests.trim().isNotEmpty;
      case SignupWizardStep.instagram:
        return true; // Opcional
      case SignupWizardStep.country:
        return model.country != null && model.country!.isNotEmpty;
      case SignupWizardStep.origin:
        return model.originSource != null && model.originSource!.isNotEmpty;
      case SignupWizardStep.evaluation:
        return true; // Opcional/Informativo
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
      'gender': '', // Será preenchido posteriormente
      'sexualOrientation': '', // Será preenchido posteriormente
      'birthDay': model.userBirthDay,
      'birthMonth': model.userBirthMonth,
      'birthYear': model.userBirthYear,
      'age': model.age, // Idade calculada automaticamente
      'interests': model.interests.trim(),
      'instagram': model.instagram.trim(), // Usuário do Instagram
      'jobTitle': '', // Será preenchido posteriormente
      'bio': model.bio.trim(), // Obrigatório
      'from': model.country ?? '', // País do usuário
      'flag': model.countryFlag ?? '', // Bandeira emoji do país
      'originSource': model.originSource ?? '',
      'agreeTerms': model.agreeTerms,
      'vip_priority': 2,
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
                  i18n.translate('ok'),
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
      case SignupWizardStep.bio:
        return i18n.translate('tell_us_about_yourself');
      case SignupWizardStep.interests:
        return i18n.translate('select_interests');
      case SignupWizardStep.instagram:
        return i18n.translate('instagram_username');
      case SignupWizardStep.country:
        return i18n.translate('select_country');
      case SignupWizardStep.origin:
        return i18n.translate('how_did_you_hear_about_us');
      case SignupWizardStep.evaluation:
        return i18n.translate('what_people_are_saying');
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
      case SignupWizardStep.bio:
        return i18n.translate('share_a_bit_about_yourself');
      case SignupWizardStep.interests:
        return i18n.translate('select_activity_categories');
      case SignupWizardStep.instagram:
        return i18n.translate('instagram_subtitle');
      case SignupWizardStep.country:
        return i18n.translate('country_subtitle');
      case SignupWizardStep.origin:
        return i18n.translate('we_would_love_to_know');
      case SignupWizardStep.evaluation:
        return i18n.translate('see_what_our_community_thinks');
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
              backgroundColor: isOnboarding ? Colors.black : Colors.white,
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
              showLogo: _wizardViewModel.isFirstStep,
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
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ProfilePhotoWidget(
              imageFile: _cadastroViewModel.imageFile as File?,
              onImageSelected: (file) => _cadastroViewModel.setImageFile(file),
            ),
          ),
        );
      
      case SignupWizardStep.personalInfo:
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
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
          ),
        );
      
      case SignupWizardStep.bio:
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: BioWidget(
              initialBio: _cadastroViewModel.bio,
              onBioChanged: _cadastroViewModel.setBio,
            ),
          ),
        );
      
      case SignupWizardStep.interests:
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SpecialtySelectorWidget(
              initialSpecialty: _cadastroViewModel.interests,
              onSpecialtyChanged: (value) => _cadastroViewModel.setInterests(value ?? ''),
            ),
          ),
        );
      
      case SignupWizardStep.instagram:
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: InstagramWidget(
              initialInstagram: _cadastroViewModel.instagram,
              onInstagramChanged: (value) {
                _cadastroViewModel.setInstagram(value);
                _onCadastroChanged(); // Força update do botão
              },
            ),
          ),
        );
      
      case SignupWizardStep.country:
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: CountrySelectorWidget(
              initialCountry: _cadastroViewModel.country,
              onCountryChanged: (countryData) {
                if (countryData != null) {
                  _cadastroViewModel.setCountry(countryData.name);
                  _cadastroViewModel.setCountryFlag(countryData.flag);
                } else {
                  _cadastroViewModel.setCountry(null);
                  _cadastroViewModel.setCountryFlag(null);
                }
                _onCadastroChanged(); // Força update do botão
              },
            ),
          ),
        );
      
      case SignupWizardStep.origin:
        return Container(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: OriginSelectorWidget(
              initialOrigin: _cadastroViewModel.originSource,
              onOriginChanged: (value) {
                _cadastroViewModel.originSource = value;
                _onCadastroChanged(); // Força update do botão
              },
            ),
          ),
        );

      case SignupWizardStep.evaluation:
        return Container(
          color: Colors.white,
          child: const SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: AppEvaluationWidget(
              isBride: false, // Vendor flow
              shouldAutoRequestReview: true,
            ),
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
              showLogo: _wizardViewModel.isFirstStep,
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
