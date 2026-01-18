import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/skeletons/profile_header_skeleton.dart';
import 'package:partiu/shared/widgets/reactive/reactive_widgets.dart';
import 'package:partiu/shared/widgets/glimpse_tab_app_bar.dart';
import 'package:partiu/shared/widgets/verification_card.dart';
import 'package:partiu/shared/widgets/image_source_bottom_sheet.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/features/profile/presentation/viewmodels/profile_tab_view_model.dart';
import 'package:partiu/features/profile/presentation/viewmodels/edit_profile_view_model_refactored.dart' as vm;
import 'package:partiu/features/profile/presentation/models/edit_profile_models.dart';
import 'package:partiu/features/profile/presentation/widgets/profile_info_chips.dart';
import 'package:partiu/features/profile/presentation/widgets/app_section_card.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_router.dart';
import 'package:partiu/features/profile/presentation/screens/profile_screen_optimized.dart';
import 'package:partiu/core/services/distance_unit_service.dart';

// ==================== PERFORMANCE OPTIMIZATIONS ====================
// Seguindo BOAS_PRATICAS2.MD:
// - Widgets const para evitar reconstruções
// - Cache de SVGs e TextStyles
// - Separação de responsabilidades para rebuild seletivo
//
// ==================== MVVM IMPROVEMENTS ====================
// Seguindo BOAS_PRATICAS.MD:
// - [OK] View não contém lógica de negócio
// - [OK] ViewModel não depende de BuildContext
// - [OK] Commands separam preparação de execução
// - [OK] Injeção de dependência explícita no ViewModel

/// ProfileTab - View pura seguindo padrão MVVM
/// 
/// Responsabilidades:
/// - Renderizar UI baseada no estado do ViewModel
/// - Delegar ações do usuário ao ViewModel (preparação)
/// - Executar navegação com BuildContext (após validação do ViewModel)
/// - Não conter lógica de negócio
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  ProfileTabViewModel? _viewModel;
  
  // Cache de TextStyles para evitar recriação a cada build
  late TextStyle _nameTextStyle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Inicializa ViewModel apenas uma vez usando didChangeDependencies
    if (_viewModel == null) {
      final serviceLocator = DependencyProvider.of(context).serviceLocator;
      _viewModel = serviceLocator.get<ProfileTabViewModel>();
      
      // ✅ PRELOAD: Carregar avatar do usuário antes da UI renderizar
      final user = _viewModel!.currentUser;
      if (user != null && user.photoUrl != null && user.photoUrl!.isNotEmpty) {
        UserStore.instance.preloadAvatar(user.userId, user.photoUrl!);
      }
      
      // Inicializa completeness check após primeiro frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _viewModel!.shouldCheckCompleteness()) {
          _viewModel!.executeCompletenessCheck(context);
        }
      });
    }
    
    // Cache de TextStyle - recriado apenas quando tema muda
    _nameTextStyle = GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
      color: Theme.of(context).textTheme.bodyLarge?.color,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    );
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  // ==================== EVENT HANDLERS ====================
  
  /// Handler: Navegar para visualização de perfil
  /// Usa Command pattern - ViewModel valida, View executa navegação
  Future<void> _handleViewProfileTap(BuildContext context) async {
    final command = _viewModel?.prepareViewProfileNavigation();
    
    if (command == null) {
      // Usuário não autenticado - mostra feedback
      if (mounted) {
        final i18n = AppLocalizations.of(context);
        ToastService.showError(
          message: i18n.translate('profile_not_found'),
        );
      }
      return;
    }
    
    try {
      // Navega para o próprio perfil usando ProfileScreenOptimized
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProfileScreenOptimized(
            user: command.user,
            currentUserId: command.user.userId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).translate('error_loading_profile'));
      }
    }
  }

  /// Exibe toast de erro
  void _showError(String message) {
    ToastService.showError(message: message);
  }
  
  /// Handler: Navegar para edição de perfil
  Future<void> _handleEditProfileTap(BuildContext context) async {
    final command = _viewModel?.prepareEditProfileNavigation();
    
    if (command == null) {
      if (mounted) {
        _showError(AppLocalizations.of(context).translate('user_not_authenticated'));
      }
      return;
    }
    
    try {
      await ProfileScreenRouter.navigateToEditProfile(context);
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).translate('error_opening_edit_profile'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    String tr(String key, String fallback) {
      final value = i18n.translate(key);
      return value.isNotEmpty ? value : fallback;
    }

    // Aguarda inicialização do ViewModel
    if (_viewModel == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel!,
          builder: (context, _) {
            return SingleChildScrollView(
              physics: GlimpseStyles.scrollPhysics,
              child: Column(
                children: [
                  GlimpseTabAppBar(
                    title: tr('profile', 'Perfil'),
                    actions: [
                      GlimpseTabActionButton(
                        icon: Iconsax.user,
                        tooltip: tr('view_profile', 'Ver Perfil'),
                        onPressed: () => _handleViewProfileTap(context),
                      ),
                      const SizedBox(width: 16),
                      GlimpseTabActionButton(
                        icon: Iconsax.edit,
                        tooltip: tr('edit_profile', 'Editar Perfil'),
                        onPressed: () => _handleEditProfileTap(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Profile header content
                  _ProfileHeaderContent(
                    viewModel: _viewModel!,
                    nameTextStyle: _nameTextStyle,
                    onEditProfile: () => _handleEditProfileTap(context),
                  ),
                  const SizedBox(height: GlimpseStyles.mediumSpacing),

                  /// App Section Card
                  ChangeNotifierProvider(
                    create: (_) => DistanceUnitService(),
                    child: const AppSectionCard(),
                  ),

                  const SizedBox(height: 25),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== OPTIMIZED WIDGETS ====================

/// Conteúdo do header do perfil (avatar, nome, chips)
class _ProfileHeaderContent extends StatelessWidget {
  
  const _ProfileHeaderContent({
    required this.viewModel,
    required this.nameTextStyle,
    required this.onEditProfile,
  });
  final ProfileTabViewModel viewModel;
  final TextStyle nameTextStyle;
  final VoidCallback onEditProfile;

  /// Handler para upload de foto de perfil
  Future<void> _handlePhotoUpload(BuildContext context) async {
    final i18n = AppLocalizations.of(context);
    
    try {
      // Abre bottom sheet para seleção de foto
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return ImageSourceBottomSheet(
            onImageSelected: (file) async {
              // Upload da imagem
              await _uploadProfilePhoto(context, file);
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
      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('error_selecting_photo'),
        );
      }
    }
  }

  /// Faz upload da foto de perfil
  Future<void> _uploadProfilePhoto(BuildContext context, File imageFile) async {
    final i18n = AppLocalizations.of(context);
    
    try {
      // Mostra loading
      if (context.mounted) {
        ToastService.showInfo(
          message: i18n.translate('uploading_photo'),
        );
      }

      // Faz upload usando EditProfileViewModel
      final serviceLocator = DependencyProvider.of(context).serviceLocator;
      final editViewModel = serviceLocator.get<vm.EditProfileViewModelRefactored>();
      
      final result = await editViewModel.handleUpdatePhoto(imageFile);
      
      if (result is PhotoUploadResultSuccess) {
        if (context.mounted) {
          ToastService.showSuccess(
            message: i18n.translate('photo_updated_successfully'),
          );
        }
      } else if (result is PhotoUploadResultFailure) {
        if (context.mounted) {
          ToastService.showError(
            message: result.errorDetails ?? i18n.translate('error_updating_photo'),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error uploading photo: $e');
      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('error_updating_photo'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = viewModel.currentUser;
    
    // Show skeleton if user data is not loaded yet
    if (!viewModel.isUserDataLoaded || user == null) {
      return const ProfileHeaderSkeleton();
    }
    
    // Show actual profile data
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          // Avatar com Progress Ring REATIVO
          Center(
            child: ValueListenableBuilder<User?>(
              valueListenable: AppState.currentUser,
              builder: (context, currentUser, _) {
                if (currentUser == null) {
                  return const SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(),
                  );
                }
                
                return ReactiveProfileCompletenessRing(
                  size: 98,
                  strokeWidth: 3,
                  child: StableAvatar(
                    userId: currentUser.userId,
                    size: 88,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    photoUrl: currentUser.photoUrl,
                    enableNavigation: false,
                    onTap: () => _handlePhotoUpload(context),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          
          // Nome completo
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ReactiveUserNameWithBadge(
                userId: user.userId,
                style: nameTextStyle,
                iconSize: 14,
                spacing: 6,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 0),
          
          // Localização como texto
          _LocationText(user: user),
          const SizedBox(height: 16),
          
          // Localização + Visits
          const ProfileInfoChips(),
          const SizedBox(height: 16),
          
          // Verification Card (só exibe se NÃO estiver verificado)
          ValueListenableBuilder<User?>(
            valueListenable: AppState.currentUser,
            builder: (context, user, _) {
              if (user == null) return const SizedBox.shrink();
              
              return ValueListenableBuilder<bool>(
                valueListenable: UserStore.instance.getVerifiedNotifier(user.userId),
                builder: (context, isVerified, _) {
                  if (isVerified) {
                    return const SizedBox.shrink();
                  }
                  
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: GlimpseStyles.horizontalMargin),
                    child: VerificationCard(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Widget para mostrar localização como texto simples
class _LocationText extends StatelessWidget {
  const _LocationText({required this.user});
  
  final User user;

  @override
  Widget build(BuildContext context) {
    final city = user.userLocality;
    final state = user.userState;
    
    // Se não tem localização, não mostra nada
    if ((city == null || city.isEmpty) && (state == null || state.isEmpty)) {
      return const SizedBox.shrink();
    }
    
    // Constrói o texto da localização
    final locationText = city?.isNotEmpty == true
        ? ((state?.isNotEmpty == true) ? "$city, $state" : city!)
        : ((state?.isNotEmpty == true) ? state! : '');
    
    if (locationText.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          locationText,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            color: GlimpseColors.textSubTitle,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
