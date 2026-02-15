import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/features/location/presentation/viewmodels/update_location_view_model.dart';
import 'package:partiu/core/services/location_service.dart';
import 'package:partiu/core/services/location_permission_flow.dart';
import 'package:partiu/core/utils/geohash_helper.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:geolocator/geolocator.dart';
import 'package:iconsax/iconsax.dart';

/// Tela de autorização de localização - UI inspirada no design do Nomadtable
/// 
/// Este widget exibe uma tela de permissão sem mapa.
/// Usa os novos serviços:
/// - LocationPermissionFlow para gerenciar permissões
/// - LocationService para obter coordenadas
/// - UpdateLocationViewModel para salvar no Firestore
class UpdateLocationScreenRefactored extends StatefulWidget {

  const UpdateLocationScreenRefactored({
    super.key,
    this.isSignUpProcess = true,
    this.isFromEditProfile = false,
  });
  
  final bool isSignUpProcess;
  final bool isFromEditProfile;

  @override
  UpdateLocationScreenRefactoredState createState() => UpdateLocationScreenRefactoredState();
}

class UpdateLocationScreenRefactoredState extends State<UpdateLocationScreenRefactored> {
  late AppLocalizations _i18n;
  late UpdateLocationViewModel _viewModel;
  late LocationService _locationService;
  late LocationPermissionFlow _permissionFlow;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Obtém serviços via DI
    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    _viewModel = serviceLocator.get<UpdateLocationViewModel>();
    _locationService = serviceLocator.get<LocationService>();
    _permissionFlow = serviceLocator.get<LocationPermissionFlow>();
    _i18n = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Processa o salvamento da localização usando os novos serviços
  Future<void> _handleSaveLocation() async {
    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    
    if (userId == null) {
      _showErrorDialog(_i18n.translate('user_not_logged_in'));
      return;
    }
    
    // Mostra loading no botão
    setState(() => _isSaving = true);
    
    try {
      // 1. Solicita permissão usando LocationPermissionFlow
      final permission = await _permissionFlow.resolvePermission();
      
      if (permission == LocationPermission.deniedForever) {
        // Usuário negou permanentemente
        if (mounted) setState(() => _isSaving = false);
        _showPermissionDeniedForeverDialog();
        return;
      }
      
      if (permission == LocationPermission.denied) {
        // Usuário negou agora
        if (mounted) setState(() => _isSaving = false);
        _showErrorDialog(_i18n.translate('location_permission_required'));
        return;
      }
      
      // 2. Verifica se GPS está habilitado
      final gpsEnabled = await _permissionFlow.isGpsEnabled();
      if (!gpsEnabled) {
        if (mounted) setState(() => _isSaving = false);
        _showErrorDialog(_i18n.translate('please_enable_gps'));
        return;
      }
      
      // 3. Obtém localização via LocationService
      final position = await _locationService.getCurrentLocation(
        timeout: const Duration(seconds: 10),
      );
      
      if (position == null) {
        if (mounted) setState(() => _isSaving = false);
        _showErrorDialog(_i18n.translate('location_not_available'));
        return;
      }
      
      final geohash = GeohashHelper.encode(
        position.latitude,
        position.longitude,
        precision: 7,
      );

      // 4. Salva no Firestore via ViewModel
      await _viewModel.saveLocationDirectly(
        userId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
        geohash: geohash,
      );
      
      // Aguarda o estado mudar
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Esconde loading
      if (mounted) setState(() => _isSaving = false);
      
      // 5. Trata o resultado baseado no estado
      if (_viewModel.saveState == LocationSaveState.success) {
        _showSuccessDialog(
          message: _i18n.translate("location_updated_successfully"),
          location: _viewModel.savedLocation,
          onConfirm: () {
            if (widget.isSignUpProcess) {
              context.go('${AppRoutes.home}?tab=0');
            } else {
              // Se veio do edit profile, volta para a tela anterior
              Navigator.of(context).pop(true);
            }
          },
        );
      } else if (_viewModel.saveState == LocationSaveState.error) {
        _showErrorDialog(_viewModel.saveError ?? _i18n.translate('unknown_error'));
      }
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
      _showErrorDialog('${_i18n.translate('error_getting_location')}: $e');
    }
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: DialogStyles.containerBorderRadius),
        child: Padding(
          padding: DialogStyles.containerPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogStyles.buildWarningIcon(icon: Iconsax.close_circle, iconSize: 40.w),
              const SizedBox(height: DialogStyles.spacingAfterIcon),
              DialogStyles.buildTitle(_i18n.translate('error')),
              const SizedBox(height: DialogStyles.spacingAfterTitle),
              DialogStyles.buildMessage(message),
              const SizedBox(height: DialogStyles.spacingBeforeButtons),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: DialogStyles.positiveButtonStyle,
                  child: Text(_i18n.translate('ok'), style: DialogStyles.positiveButtonTextStyle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showSuccessDialog({
    required String message,
    String? location,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // Impede fechar tocando fora
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: DialogStyles.containerBorderRadius),
        child: Padding(
          padding: DialogStyles.containerPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogStyles.buildSuccessIcon(icon: Iconsax.tick_circle, iconSize: 40.w),
              const SizedBox(height: DialogStyles.spacingAfterIcon),
              DialogStyles.buildTitle(_i18n.translate('success')),
              const SizedBox(height: DialogStyles.spacingAfterTitle),
              DialogStyles.buildMessage(message),
              // Localidade destacada com cor primaryLight
              if (location != null && location.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: GlimpseColors.primaryLight,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Iconsax.location,
                        size: 18.w,
                        color: GlimpseColors.primary,
                      ),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          location,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: GlimpseColors.primaryColorLight,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DialogStyles.spacingBeforeButtons),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext); // Fecha o dialog
                    onConfirm(); // Navega imediatamente
                  },
                  style: DialogStyles.successButtonStyle,
                  child: Text(_i18n.translate('ok'), style: DialogStyles.successButtonTextStyle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showPermissionDeniedForeverDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: DialogStyles.containerBorderRadius),
        child: Padding(
          padding: DialogStyles.containerPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogStyles.buildWarningIcon(icon: Iconsax.location_slash, iconSize: 40.w),
              const SizedBox(height: DialogStyles.spacingAfterIcon),
              DialogStyles.buildTitle(_i18n.translate('permission_required')),
              const SizedBox(height: DialogStyles.spacingAfterTitle),
              DialogStyles.buildMessage(
                _i18n.translate('location_permission_denied_forever_message'),
              ),
              const SizedBox(height: DialogStyles.spacingBeforeButtons),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Abre configurações do app
                    Geolocator.openAppSettings();
                  },
                  style: DialogStyles.positiveButtonStyle,
                  child: Text(
                    _i18n.translate('open_settings'),
                    style: DialogStyles.positiveButtonTextStyle,
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _i18n.translate('cancel'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _i18n = AppLocalizations.of(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.isFromEditProfile
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: Padding(
                padding: EdgeInsets.only(left: 16.w),
                child: GlimpseBackButton(
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              leadingWidth: 56.w,
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, child) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
                      child: Column(
                        children: [
                          // Logo/ícone principal
                          Container(
                            width: 80.w,
                            height: 80.h,
                            decoration: BoxDecoration(
                              color: GlimpseColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Iconsax.location,
                              size: 40.w,
                              color: GlimpseColors.primary,
                            ),
                          ),
                          
                          SizedBox(height: 40.h),
                          
                          // Título principal
                          Text(
                            _i18n.translate('connect_with_nearby_travelers'),
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 28.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          
                          SizedBox(height: 16.h),
                          
                          // Subtítulo
                          Text(
                            _i18n.translate('enable_location_to_discover'),
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          
                          SizedBox(height: 24.h),
                          
                          // Lista de benefícios
                          _buildBenefitItem(
                            icon: Iconsax.map_1,
                            title: _i18n.translate('discover_nearby_activities'),
                            description: _i18n.translate('find_and_join_spontaneous_meetups'),
                          ),
                          
                          SizedBox(height: 32.h),
                          
                          _buildBenefitItem(
                            icon: Iconsax.people,
                            title: _i18n.translate('appear_to_nearby_travelers'),
                            description: _i18n.translate('other_travelers_can_see_you'),
                          ),
                          
                          SizedBox(height: 32.h),
                          
                          _buildBenefitItem(
                            icon: Iconsax.shield_tick,
                            title: _i18n.translate('your_privacy_is_protected'),
                            description: _i18n.translate('exact_location_never_shown'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        
          // Botão fixado na parte inferior com SafeArea
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: GlimpseButton(
                text: _i18n.translate('enable_and_continue'),
                onPressed: _handleSaveLocation,
                isProcessing: _isSaving,
                width: double.infinity,
                height: 56.h,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Widget para criar cada item de benefício
  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48.w,
          height: 48.h,
          decoration: BoxDecoration(
            color: GlimpseColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 24.w,
            color: GlimpseColors.primary,
          ),
        ),
        
        SizedBox(width: 16.w),
        
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              
              SizedBox(height: 4.h),
              
              Text(
                description,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  

}
