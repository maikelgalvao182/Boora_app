import 'dart:io';

import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/app/services/localization_service.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/profile/presentation/viewmodels/app_section_view_model.dart';
import 'package:partiu/features/profile/presentation/widgets/dialogs/delete_account_confirm_dialog.dart';
import 'package:partiu/core/services/distance_unit_service.dart';
import 'package:partiu/app/services/locale_service.dart';
import 'package:partiu/shared/widgets/dialogs/language_selector_dialog.dart';
import 'package:partiu/core/helpers/app_helper.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:partiu/core/constants/constants.dart';

class AppSectionCard extends StatefulWidget {
  const AppSectionCard({super.key});

  @override
  State<AppSectionCard> createState() => _AppSectionCardState();
}

class _AppSectionCardState extends State<AppSectionCard> {
  final AppHelper _appHelper = AppHelper();
  AppSectionViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= AppSectionViewModel();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = LocalizationService.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Distance Unit Toggle (km/mi)
          Consumer<DistanceUnitService>(
            builder: (context, distanceService, _) {
              return _buildSwitchItem(
                context,
                icon: Iconsax.routing,
                title: i18n.translate('distance_unit') ?? 'Unidade de Distância',
                subtitle: distanceService.useMiles ? 'Miles (mi)' : 'Kilometers (km)',
                value: distanceService.useMiles,
                onChanged: (value) async {
                  HapticFeedback.lightImpact();
                  await distanceService.toggleUnit();
                },
              );
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Icons.language,
            title: i18n.translate('language') ?? 'Idioma',
            onTap: () {
              final localeService = Provider.of<LocaleService>(context, listen: false);
              LanguageSelectorDialog.show(context, localeService);
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.location,
            title: 'Teste Location Picker',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LocationPickerPageRefactored(),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.heart,
            title: i18n.translate('likes') ?? 'Curtidas',
            onTap: () {
              // TODO: Implementar navegação para tela de likes
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.user_remove,
            title: i18n.translate('blocked_users') ?? 'Usuários Bloqueados',
            onTap: () {
              // TODO: Implementar navegação para usuários bloqueados
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.info_circle,
            title: i18n.translate('about_us') ?? 'Sobre Nós',
            onTap: () {
              // TODO: Implementar navegação para sobre nós
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.share,
            title: i18n.translate('share_with_friends') ?? 'Compartilhar com Amigos',
            onTap: () async {
              _appHelper.shareApp(context: context);
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.star,
            title: Platform.isAndroid
                ? (i18n.translate('rate_on_play_store') ?? 'Avaliar na Play Store')
                : (i18n.translate('rate_on_app_store') ?? 'Avaliar na App Store'),
            onTap: () async {
              _appHelper.reviewApp();
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.shield_tick,
            title: i18n.translate('privacy_policy') ?? 'Política de Privacidade',
            onTap: () async {
              _appHelper.openPrivacyPage();
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.document_text,
            title: i18n.translate('terms_of_service') ?? 'Termos de Serviço',
            onTap: () async {
              _appHelper.openTermsPage();
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          _buildListItem(
            context,
            icon: Iconsax.logout,
            title: i18n.translate('sign_out') ?? 'Sair',
            onTap: () => _handleLogout(context, i18n),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
          
          _buildListItem(
            context,
            icon: Iconsax.trash,
            title: i18n.translate('delete_account') ?? 'Excluir Conta',
            iconColor: Colors.red,
            textColor: Colors.red,
            onTap: () {
              DeleteAccountConfirmDialog.show(
                context,
                iconData: Iconsax.trash,
                title: '${i18n.translate("delete_account") ?? "Excluir Conta"} ?',
                message: i18n.translate('all_your_profile_data_will_be_permanently_deleted') ?? 
                    'Todos os seus dados de perfil serão permanentemente excluídos',
                negativeText: i18n.translate('CANCEL') ?? 'CANCELAR',
                positiveText: i18n.translate('DELETE') ?? 'EXCLUIR',
                negativeAction: () => Navigator.of(context).pop(),
                positiveAction: () async {
                  final navigator = Navigator.of(context);
                  Future(() => navigator.pop());

                  _viewModel?.signOut().then((_) {
                    Future(() {
                      navigator.popUntil((route) => route.isFirst);
                      // TODO: Implementar tela de exclusão de conta
                      // navigator.pushReplacement(MaterialPageRoute(
                      //     builder: (context) => const DeleteAccountScreen()));
                    });
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }
  
  /// Executa logout com loading e navegação via go_router
  Future<void> _handleLogout(BuildContext context, LocalizationService i18n) async {
    final progressDialog = ProgressDialog(context);
    
    try {
      // Mostra loading
      progressDialog.show(i18n.translate('signing_out') ?? 'Saindo...');
      
      // Executa logout (processo de 9 etapas)
      await _viewModel?.signOut();
      
      // Esconde loading
      await progressDialog.hide();
      
      // Aguarda frame para garantir que dialog foi fechado
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Navega para login usando go_router (declarative navigation)
      if (mounted) {
        context.go(AppRoutes.signIn);
      }
    } catch (e) {
      debugPrint('❌ Erro durante logout: $e');
      
      // Tenta esconder loading mesmo com erro
      try {
        await progressDialog.hide();
      } catch (_) {}
      
      // Navega mesmo assim (logout provavelmente foi executado)
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        context.go(AppRoutes.signIn);
      }
    }
  }

  Widget _buildSwitchItem(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GlimpseColors.lightTextField,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.60),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Transform.scale(
            scale: 0.85,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: GlimpseColors.primary,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildListItem(BuildContext context, {
    required IconData icon, 
    required String title, 
    required VoidCallback? onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return InkWell(
      onTap: onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GlimpseColors.lightTextField,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: textColor ?? Colors.black,
                  ),
                ),
              ],
            ),
            Icon(Iconsax.arrow_right_3, size: 20, color: Theme.of(context).iconTheme.color!.withValues(alpha: 0.50)),
          ],
        ),
      ),
    );
  }
}
