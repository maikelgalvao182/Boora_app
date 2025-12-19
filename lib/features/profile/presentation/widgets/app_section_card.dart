import 'dart:io';

import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/app/services/localization_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/profile/presentation/viewmodels/app_section_view_model.dart';
import 'package:partiu/features/profile/presentation/widgets/dialogs/delete_account_confirm_dialog.dart';
import 'package:partiu/features/auth/presentation/widgets/app_evaluation_widget.dart';
import 'package:partiu/app/services/locale_service.dart';
import 'package:partiu/shared/widgets/dialogs/language_selector_dialog.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/core/helpers/app_helper.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/push_types.dart';
import 'package:partiu/core/services/push_preferences_service.dart';
import 'package:partiu/core/managers/session_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Seção: Notificações
        _buildSectionHeader(context, i18n.translate('section_notifications') ?? 'Notificações'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildSwitchItem(
                context,
                icon: Iconsax.notification,
                title: i18n.translate('global_notifications') ?? 'Notificações gerais',
                value: PushPreferencesService.isEnabled(
                  PushType.global,
                  SessionManager.instance.currentUser?.pushPreferences,
                ),
                onChanged: (v) => _updatePushPreference(PushType.global, v),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildSwitchItem(
                context,
                icon: Iconsax.message,
                title: i18n.translate('event_messages') ?? 'Mensagens dos eventos',
                value: PushPreferencesService.isEnabled(
                  PushType.chatEvent,
                  SessionManager.instance.currentUser?.pushPreferences,
                ),
                onChanged: (v) => _updatePushPreference(PushType.chatEvent, v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Visibilidade
        _buildSectionHeader(context, i18n.translate('section_visibility') ?? 'Visibilidade'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildListItem(
                context,
                icon: Iconsax.user_remove,
                title: i18n.translate('blocked_users') ?? 'Usuários Bloqueados',
                onTap: () {
                  context.push(AppRoutes.blockedUsers);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Suporte
        _buildSectionHeader(context, i18n.translate('section_support') ?? 'Suporte'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildListItem(
                context,
                icon: Iconsax.shield_tick,
                title: i18n.translate('safety_and_etiquette') ?? 'Segurança e Etiqueta',
                onTap: () async {
                  _appHelper.openSafetyPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.document_text_1,
                title: i18n.translate('community_guidelines') ?? 'Diretrizes da Comunidade',
                onTap: () async {
                  _appHelper.openGuidelinesPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.info_circle,
                title: i18n.translate('about_us') ?? 'Sobre Nós',
                onTap: () async {
                  _appHelper.openAboutPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.message_question,
                title: i18n.translate('report_bug') ?? 'Reportar um Bug',
                onTap: () async {
                  _appHelper.openBugReport();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Social
        _buildSectionHeader(context, i18n.translate('section_social') ?? 'Social'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
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
                onTap: () => _showReviewDialog(context),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItemWithImage(
                context,
                imagePath: 'assets/svg/tiktok2.svg',
                title: i18n.translate('follow_us_on_tiktok') ?? 'Seguir no TikTok',
                onTap: () async {
                  _appHelper.openUrl('https://www.tiktok.com/@booraapp');
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: IconsaxPlusLinear.instagram,
                title: i18n.translate('follow_us_on_instagram') ?? 'Seguir no Instagram',
                onTap: () async {
                  _appHelper.openUrl('https://www.instagram.com/booraapp');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Legal
        _buildSectionHeader(context, i18n.translate('section_legal') ?? 'Legal'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildListItem(
                context,
                icon: Iconsax.lock,
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
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Conta
        _buildSectionHeader(context, i18n.translate('section_account') ?? 'Conta'),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildListItem(
                context,
                icon: Iconsax.logout,
                title: i18n.translate('sign_out') ?? 'Sair',
                onTap: () {
                  debugPrint('🚪 [LOGOUT] Botão de logout clicado');
                  _handleLogout(context, i18n);
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.trash,
                title: i18n.translate('delete_account') ?? 'Excluir Conta',
                iconColor: Colors.red,
                textColor: Colors.red,
                onTap: () => _handleDeleteAccount(context, i18n),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// Executa logout com loading e navegação via go_router
  Future<void> _handleLogout(BuildContext context, LocalizationService i18n) async {
    debugPrint('🚪 [LOGOUT] Iniciando processo de logout');
    
    // IMPORTANTE: Capturar GoRouter ANTES de qualquer operação assíncrona
    // para evitar "Looking up a deactivated widget's ancestor is unsafe"
    final router = GoRouter.of(context);
    debugPrint('🚪 [LOGOUT] GoRouter capturado');
    
    final progressDialog = ProgressDialog(context);
    
    try {
      // Mostra loading
      debugPrint('🚪 [LOGOUT] Mostrando dialog de progresso');
      progressDialog.show(i18n.translate('signing_out') ?? 'Saindo...');
      
      // Executa logout (processo de 9 etapas)
      debugPrint('🚪 [LOGOUT] Chamando _viewModel.signOut()');
      await _viewModel?.signOut();
      debugPrint('🚪 [LOGOUT] ✅ signOut() concluído');
      
      // Esconde loading
      debugPrint('🚪 [LOGOUT] Escondendo dialog de progresso');
      await progressDialog.hide();
      debugPrint('🚪 [LOGOUT] ✅ Dialog escondido');
      
      // Navega usando GoRouter capturado (não usa context)
      debugPrint('🚪 [LOGOUT] Navegando para ${AppRoutes.signIn} via GoRouter');
      router.go(AppRoutes.signIn);
      debugPrint('🚪 [LOGOUT] ✅ Navegação concluída');
      
    } catch (e, stackTrace) {
      debugPrint('🚪 [LOGOUT] ❌ Erro durante logout: $e');
      debugPrint('🚪 [LOGOUT] ❌ StackTrace: $stackTrace');
      
      // Tenta esconder loading mesmo com erro
      try {
        debugPrint('🚪 [LOGOUT] Tentando esconder dialog após erro');
        await progressDialog.hide();
        debugPrint('🚪 [LOGOUT] ✅ Dialog escondido após erro');
      } catch (dialogError) {
        debugPrint('🚪 [LOGOUT] ❌ Erro ao esconder dialog: $dialogError');
      }
      
      // Navega mesmo assim usando GoRouter capturado
      debugPrint('🚪 [LOGOUT] Navegando para ${AppRoutes.signIn} (após erro)');
      router.go(AppRoutes.signIn);
      debugPrint('🚪 [LOGOUT] ✅ Navegação concluída (após erro)');
    }
  }
  
  /// Executa exclusão de conta com confirmação e Cloud Function
  Future<void> _handleDeleteAccount(BuildContext context, LocalizationService i18n) async {
    debugPrint('🗑️ [DELETE_ACCOUNT] Iniciando processo de exclusão de conta');
    
    // Capturar GoRouter e userId ANTES de operações assíncronas
    final router = GoRouter.of(context);
    final userId = AppState.currentUserId;
    
    if (userId == null || userId.isEmpty) {
      debugPrint('🗑️ [DELETE_ACCOUNT] ❌ Usuário não autenticado');
      return;
    }
    
    debugPrint('🗑️ [DELETE_ACCOUNT] UserId: ${userId.substring(0, 8)}...');
    
    // Mostrar diálogo de confirmação usando GlimpseCupertinoDialog
    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('delete_account') ?? 'Excluir Conta',
      message: i18n.translate('all_your_profile_data_will_be_permanently_deleted') ?? 
          'Todos os seus dados de perfil serão permanentemente excluídos. Esta ação não pode ser desfeita.',
      destructiveText: i18n.translate('DELETE') ?? 'Excluir',
      cancelText: i18n.translate('CANCEL') ?? 'Cancelar',
    );
    
    if (confirmed != true) {
      debugPrint('🗑️ [DELETE_ACCOUNT] ❌ Usuário cancelou');
      return;
    }
    
    debugPrint('🗑️ [DELETE_ACCOUNT] ✅ Confirmado pelo usuário');
    
    final progressDialog = ProgressDialog(context);
    
    try {
      // Mostra loading
      debugPrint('🗑️ [DELETE_ACCOUNT] Mostrando dialog de progresso');
      progressDialog.show(i18n.translate('deleting_account') ?? 'Excluindo conta...');
      
      // Chama Cloud Function para deletar dados
      debugPrint('🗑️ [DELETE_ACCOUNT] Chamando Cloud Function deleteUserAccount');
      final callable = FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
      final result = await callable.call<Map<String, dynamic>>({
        'userId': userId,
      });
      
      debugPrint('🗑️ [DELETE_ACCOUNT] ✅ Cloud Function executada: ${result.data}');
      
      // Faz logout
      debugPrint('🗑️ [DELETE_ACCOUNT] Executando logout');
      await _viewModel?.signOut();
      debugPrint('🗑️ [DELETE_ACCOUNT] ✅ Logout concluído');
      
      // Esconde loading
      debugPrint('🗑️ [DELETE_ACCOUNT] Escondendo dialog de progresso');
      await progressDialog.hide();
      
      // Navega para tela de login
      debugPrint('🗑️ [DELETE_ACCOUNT] Navegando para ${AppRoutes.signIn}');
      router.go(AppRoutes.signIn);
      debugPrint('🗑️ [DELETE_ACCOUNT] ✅ Conta excluída com sucesso');
      
    } catch (e, stackTrace) {
      debugPrint('🗑️ [DELETE_ACCOUNT] ❌ Erro durante exclusão: $e');
      debugPrint('🗑️ [DELETE_ACCOUNT] ❌ StackTrace: $stackTrace');
      
      // Tenta esconder loading
      try {
        await progressDialog.hide();
      } catch (dialogError) {
        debugPrint('🗑️ [DELETE_ACCOUNT] ❌ Erro ao esconder dialog: $dialogError');
      }
      
      // Mostra erro ao usuário se o contexto ainda estiver montado
      if (context.mounted) {
        final i18nToast = AppLocalizations.of(context);
        ToastService.showError(
          message: i18n.translate('error_deleting_account') ?? i18nToast.translate('error_deleting_account'),
        );
      }
    }
  }
  
  /// Mostra dialog de avaliação do app
  void _showReviewDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: AppEvaluationWidget(
              isBride: false, // Vendor/Creator flow
              shouldAutoRequestReview: true,
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _updatePushPreference(PushType type, bool enabled) async {
    // 1. Update Firestore
    await PushPreferencesService.setEnabled(type, enabled);

    // 2. Update Local User (Optimistic)
    final user = SessionManager.instance.currentUser;
    if (user != null) {
      final newPrefs = Map<String, dynamic>.from(user.pushPreferences ?? {});
      newPrefs[PushPreferencesService.key(type)] = enabled;
      
      final newUser = user.copyWith(pushPreferences: newPrefs);
      await SessionManager.instance.saveUser(newUser);
      
      if (mounted) setState(() {}); // Rebuild UI
    }
  }
  
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 0),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.40),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSwitchItem(BuildContext context, {
    required IconData icon,
    required String title,
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
              Text(
                title,
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          CupertinoSwitch(
            value: value,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
            activeColor: GlimpseColors.primary,
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
  
  Widget _buildListItemWithImage(BuildContext context, {
    required String imagePath, 
    required String title, 
    required VoidCallback? onTap,
    Color? textColor,
  }) {
    final isSvg = imagePath.endsWith('.svg');
    
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
                  child: isSvg
                      ? SvgPicture.asset(
                          imagePath,
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                        )
                      : Image.asset(
                          imagePath,
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
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
