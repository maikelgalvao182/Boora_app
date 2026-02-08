import 'dart:io';

import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/features/profile/presentation/viewmodels/app_section_view_model.dart';
import 'package:partiu/features/profile/presentation/widgets/notifications_settings_drawer.dart';
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
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/controllers/locale_controller.dart';
import 'package:provider/provider.dart';

class AppSectionCard extends StatefulWidget {
  const AppSectionCard({super.key});

  @override
  State<AppSectionCard> createState() => _AppSectionCardState();
}

class _AppSectionCardState extends State<AppSectionCard> {
  final AppHelper _appHelper = AppHelper();
  AppSectionViewModel? _viewModel;

  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= AppSectionViewModel();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Seção: Notificações
        _buildSectionHeader(context, _tr(i18n, 'section_notifications', 'Notificações')),
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
                icon: Iconsax.notification,
                title: _tr(i18n, 'configure_notifications', 'Configurar notificações'),
                onTap: () => NotificationsSettingsDrawer.show(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Visibilidade
        _buildSectionHeader(context, _tr(i18n, 'section_visibility', 'Visibilidade')),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildMessageButtonSwitch(context),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildFollowButtonSwitch(context),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildShowDistanceSwitch(context),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.user_remove,
                title: _tr(i18n, 'blocked_users', 'Usuários Bloqueados'),
                onTap: () {
                  context.push(AppRoutes.blockedUsers);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Suporte
        _buildSectionHeader(context, _tr(i18n, 'section_support', 'Suporte')),
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
                title: _tr(i18n, 'safety_and_etiquette', 'Segurança e Etiqueta'),
                onTap: () async {
                  _appHelper.openSafetyPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.document_text_1,
                title: _tr(i18n, 'community_guidelines', 'Diretrizes da Comunidade'),
                onTap: () async {
                  _appHelper.openGuidelinesPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.info_circle,
                title: _tr(i18n, 'about_us', 'Sobre Nós'),
                onTap: () async {
                  _appHelper.openAboutPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.message_question,
                title: _tr(i18n, 'report_bug', 'Reportar um Bug'),
                onTap: () async {
                  _appHelper.openBugReport();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Social
        _buildSectionHeader(context, _tr(i18n, 'section_social', 'Social')),
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
                title: _tr(i18n, 'share_with_friends', 'Compartilhar com Amigos'),
                onTap: () async {
                  await _appHelper.shareApp(context: context);
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.star,
                title: Platform.isAndroid
                  ? _tr(i18n, 'rate_on_play_store', 'Avaliar na Play Store')
                  : _tr(i18n, 'rate_on_app_store', 'Avaliar na App Store'),
                onTap: () => _requestAppReview(),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItemWithImage(
                context,
                imagePath: 'assets/svg/tiktok2.svg',
                title: _tr(i18n, 'follow_us_on_tiktok', 'Seguir no TikTok'),
                onTap: () async {
                  _appHelper.openUrl(TIKTOK_URL);
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: IconsaxPlusLinear.instagram,
                title: _tr(i18n, 'follow_us_on_instagram', 'Seguir no Instagram'),
                onTap: () async {
                  _appHelper.openUrl(INSTAGRAM_URL);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Legal
        _buildSectionHeader(context, _tr(i18n, 'section_legal', 'Legal')),
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
                title: _tr(i18n, 'privacy_policy', 'Política de Privacidade'),
                onTap: () async {
                  _appHelper.openPrivacyPage();
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.document_text,
                title: _tr(i18n, 'terms_of_service', 'Termos de Serviço'),
                onTap: () async {
                  _appHelper.openTermsPage();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Seção: Conta
        _buildSectionHeader(context, _tr(i18n, 'section_account', 'Conta')),
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
                icon: Iconsax.global,
                title: _tr(i18n, 'language', 'Idioma'),
                onTap: () => _showLanguageSheet(context),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.logout,
                title: _tr(i18n, 'sign_out', 'Sair'),
                onTap: () {
                  debugPrint('🚪 [LOGOUT] Botão de logout clicado');
                  _handleLogout(context);
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.10)),
              _buildListItem(
                context,
                icon: Iconsax.trash,
                title: _tr(i18n, 'delete_account', 'Excluir Conta'),
                iconColor: Colors.red,
                textColor: Colors.red,
                onTap: () => _handleDeleteAccount(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    final localeController = context.read<LocaleController>();
    final effectiveLang = (localeController.overrideLanguageCode ??
            Localizations.localeOf(context).languageCode)
        .toLowerCase();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: false,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final i18n = AppLocalizations.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(i18n, 'language', 'Idioma'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _LanguageCard(
                        assetPath: 'assets/svg/BR.svg',
                        label: 'Português',
                        isSelected: effectiveLang == 'pt',
                        onTap: () async {
                          await localeController.setLocale(const Locale('pt'));
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LanguageCard(
                        assetPath: 'assets/svg/US.svg',
                        label: 'English',
                        isSelected: effectiveLang == 'en',
                        onTap: () async {
                          await localeController.setLocale(const Locale('en'));
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LanguageCard(
                        assetPath: 'assets/svg/ES.svg',
                        label: 'Español',
                        isSelected: effectiveLang == 'es',
                        onTap: () async {
                          await localeController.setLocale(const Locale('es'));
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// Executa logout com loading e navegação via go_router
  Future<void> _handleLogout(BuildContext context) async {
    debugPrint('🚪 [LOGOUT] Iniciando processo de logout');

    final i18n = AppLocalizations.of(context);
    
    // IMPORTANTE: Capturar GoRouter ANTES de qualquer operação assíncrona
    // para evitar "Looking up a deactivated widget's ancestor is unsafe"
    final router = GoRouter.of(context);
    debugPrint('🚪 [LOGOUT] GoRouter capturado');
    
    final progressDialog = ProgressDialog(context);
    
    try {
      // Mostra loading
      debugPrint('🚪 [LOGOUT] Mostrando dialog de progresso');
      progressDialog.show(_tr(i18n, 'signing_out', 'Saindo...'));
      
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
  Future<void> _handleDeleteAccount(BuildContext context) async {
    debugPrint('🗑️ [DELETE_ACCOUNT] Iniciando processo de exclusão de conta');

    final i18n = AppLocalizations.of(context);
    
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
      title: _tr(i18n, 'delete_account', 'Excluir Conta'),
      message: _tr(
        i18n,
        'all_your_profile_data_will_be_permanently_deleted',
          'Todos os seus dados de perfil serão permanentemente excluídos. Esta ação não pode ser desfeita.',
      ),
      destructiveText: _tr(i18n, 'DELETE', 'Excluir'),
      cancelText: _tr(i18n, 'CANCEL', 'Cancelar'),
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
      progressDialog.show(_tr(i18n, 'deleting_account', 'Excluindo conta...'));
      
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
        ToastService.showError(
          message: _tr(i18n, 'error_deleting_account', 'Erro ao excluir conta'),
        );
      }
    }
  }
  
  Future<void> _requestAppReview() async {
    try {
      if (!_canRequestReview()) return;
      final inAppReview = InAppReview.instance;

      // Em desenvolvimento/TestFlight, o diálogo nativo não permite enviar reviews.
      // Sempre abrir a página da loja garante que o usuário pode avaliar de verdade.
      await inAppReview.openStoreListing(appStoreId: '6755944656');
    } catch (e) {
      debugPrint('⭐️ [REVIEW] Error requesting review: $e');
    }
  }

  bool _canRequestReview() {
    if (!mounted || kIsWeb) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      return false;
    }
    return true;
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

  Widget _buildMessageButtonSwitch(BuildContext context) {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) return const SizedBox.shrink();

    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: UserStore.instance.getMessageButtonNotifier(userId),
      builder: (context, enabled, _) {
        return _buildSwitchItem(
          context,
          icon: Iconsax.message,
          title: _tr(i18n, 'message_button', 'Botão de mensagem no meu perfil'),
          value: !enabled,
          onChanged: (v) => _updateMessageButtonPreference(context, userId, !v),
        );
      },
    );
  }

  Future<void> _updateMessageButtonPreference(
    BuildContext context,
    String userId,
    bool enabled,
  ) async {
    // 1. Atualiza UI imediatamente (optimistic update)
    final notifier = UserStore.instance.getMessageButtonNotifier(userId);
    final previousValue = notifier.value;
    notifier.value = enabled;
    
    try {
      // 2. Persiste no Firestore
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .set({'message_button': enabled}, SetOptions(merge: true));

      // Compatibilidade: alguns pontos do app usam a coleção `users` (minúsculo)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'message_button': enabled}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ [MESSAGE_BUTTON] Erro ao atualizar preferência: $e');
      // Reverte para valor anterior em caso de erro
      notifier.value = previousValue;
      final i18n = AppLocalizations.of(context);
      ToastService.showError(message: _tr(i18n, 'error', 'Erro'));
    }
  }

  Widget _buildFollowButtonSwitch(BuildContext context) {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) return const SizedBox.shrink();

    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: UserStore.instance.getFollowButtonNotifier(userId),
      builder: (context, enabled, _) {
        return _buildSwitchItem(
          context,
          icon: Iconsax.user_add,
          title: _tr(i18n, 'follow_button', 'Botão de seguir no meu perfil'),
          value: !enabled,
          onChanged: (v) => _updateFollowButtonPreference(context, userId, !v),
        );
      },
    );
  }

  Future<void> _updateFollowButtonPreference(
    BuildContext context,
    String userId,
    bool enabled,
  ) async {
    // 1. Atualiza UI imediatamente (optimistic update)
    final notifier = UserStore.instance.getFollowButtonNotifier(userId);
    final previousValue = notifier.value;
    notifier.value = enabled;
    
    try {
      // 2. Persiste no Firestore (advancedSettings.followButton)
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .set({
            'advancedSettings': {
              'followButton': enabled,
            },
          }, SetOptions(merge: true));

      // Compatibilidade: alguns pontos do app usam a coleção `users` (minúsculo)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
            'advancedSettings': {
              'followButton': enabled,
            },
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ [FOLLOW_BUTTON] Erro ao atualizar preferência: $e');
      // Reverte para valor anterior em caso de erro
      notifier.value = previousValue;
      final i18n = AppLocalizations.of(context);
      ToastService.showError(message: _tr(i18n, 'error', 'Erro'));
    }
  }

  Widget _buildShowDistanceSwitch(BuildContext context) {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) return const SizedBox.shrink();

    final i18n = AppLocalizations.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: UserStore.instance.getShowDistanceNotifier(userId),
      builder: (context, enabled, _) {
        return _buildSwitchItem(
          context,
          icon: Iconsax.location,
          title: _tr(i18n, 'show_distance', 'Mostrar distância no meu perfil'),
          value: !enabled,
          onChanged: (v) => _updateShowDistancePreference(context, userId, !v),
        );
      },
    );
  }

  Future<void> _updateShowDistancePreference(
    BuildContext context,
    String userId,
    bool enabled,
  ) async {
    // 1. Atualiza UI imediatamente (optimistic update)
    final notifier = UserStore.instance.getShowDistanceNotifier(userId);
    final previousValue = notifier.value;
    notifier.value = enabled;
    
    try {
      // 2. Persiste no Firestore (advancedSettings.showDistance)
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .set({
            'advancedSettings': {
              'showDistance': enabled,
            },
          }, SetOptions(merge: true));

      // Compatibilidade: alguns pontos do app usam a coleção `users` (minúsculo)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
            'advancedSettings': {
              'showDistance': enabled,
            },
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ [SHOW_DISTANCE] Erro ao atualizar preferência: $e');
      // Reverte para valor anterior em caso de erro
      notifier.value = previousValue;
      final i18n = AppLocalizations.of(context);
      ToastService.showError(message: _tr(i18n, 'error', 'Erro'));
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

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.assetPath,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String assetPath;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? GlimpseColors.primary : Colors.black.withValues(alpha: 0.10);
    final bgColor = isSelected ? GlimpseColors.primaryLight.withValues(alpha: 0.35) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              assetPath,
              width: 36,
              height: 36,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
