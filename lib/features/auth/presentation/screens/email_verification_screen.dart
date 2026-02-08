import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/services/auth_sync_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/features/auth/presentation/controllers/sign_in_view_model.dart';
import 'package:partiu/shared/widgets/auth_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_signup_layout.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:provider/provider.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, this.email});

  final String? email;

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const String _tag = 'EmailVerificationScreen';

  late AppLocalizations _i18n;
  late SignInViewModel _signInViewModel;

  bool _isChecking = false;
  bool _isResending = false;

  final TextEditingController _emailController = TextEditingController();

  DateTime? _resendAvailableAt;
  Timer? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _i18n = AppLocalizations.of(context);

    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    _signInViewModel = serviceLocator.get<SignInViewModel>();

    final nextEmailText = _emailToShow ?? '';
    if (_emailController.text != nextEmailText) {
      _emailController.text = nextEmailText;
    }

    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_resendAvailableAt == null) return;
      if (DateTime.now().isAfter(_resendAvailableAt!)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  firebase_auth.User? get _currentUser => firebase_auth.FirebaseAuth.instance.currentUser;

  bool get _canResend {
    if (_isResending) return false;
    final at = _resendAvailableAt;
    if (at == null) return true;
    return DateTime.now().isAfter(at);
  }

  String? get _emailToShow {
    return (widget.email ?? _currentUser?.email)?.trim().isNotEmpty == true
        ? (widget.email ?? _currentUser?.email)!.trim()
        : null;
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;

    final user = _currentUser;
    if (user == null) {
      final i18n = AppLocalizations.of(context);
      ToastService.showWarning(
        message: i18n.translate('session_expired'),
      );
      return;
    }

    setState(() => _isResending = true);

    try {
      await user.sendEmailVerification();
      _resendAvailableAt = DateTime.now().add(const Duration(seconds: 60));

      AppLogger.success('E-mail de verificação reenviado', tag: _tag);

      if (!mounted) return;
      ToastService.showSuccess(
        message: _i18n.translate('email_verification_sent') != ''
            ? _i18n.translate('email_verification_sent')
            : 'E-mail de verificação enviado.',
      );
    } on firebase_auth.FirebaseAuthException catch (e, stackTrace) {
      AppLogger.error('Erro ao reenviar e-mail de verificação: ${e.code}', tag: _tag, error: e, stackTrace: stackTrace);

      if (!mounted) return;
      ToastService.showError(
        message: e.message ?? e.code,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Erro inesperado ao reenviar e-mail de verificação', tag: _tag, error: e, stackTrace: stackTrace);

      if (!mounted) return;
      ToastService.showError(message: e.toString());
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _checkEmailVerifiedAndContinue() async {
    if (_isChecking) return;

    final user = _currentUser;
    if (user == null) {
      final i18n = AppLocalizations.of(context);
      ToastService.showWarning(
        message: i18n.translate('session_expired'),
      );
      return;
    }

    setState(() => _isChecking = true);

    try {
      await user.reload();
      final refreshedUser = _currentUser;
      final isVerified = refreshedUser?.emailVerified == true;

      AppLogger.info('Checagem de emailVerified: $isVerified', tag: _tag);

      if (!mounted) return;

      if (!isVerified) {
        ToastService.showWarning(
          message: _i18n.translate('email_not_verified') != ''
              ? _i18n.translate('email_not_verified')
              : 'Seu e-mail ainda não foi confirmado. Verifique sua caixa de entrada.',
        );
        return;
      }

      // Atualiza AuthSyncService para reavaliar sessão e seguir fluxo normal
      try {
        final authSync = context.read<AuthSyncService>();
        await authSync.refreshCurrentUser();
      } catch (e, stackTrace) {
        AppLogger.warning('Falha ao forçar refresh do AuthSyncService (seguindo fluxo mesmo assim)', tag: _tag);
        AppLogger.error('Detalhes refreshCurrentUser', tag: _tag, error: e, stackTrace: stackTrace);
      }

      // Continua fluxo padrão: se tiver doc completo -> home; senão -> wizard
      await _signInViewModel.authUserAccount(
        updateLocationScreen: () {
          if (!mounted) return;
          context.go(AppRoutes.updateLocation);
        },
        signUpScreen: () {
          if (!mounted) return;
          context.go(AppRoutes.signupWizard);
        },
        homeScreen: () {
          if (!mounted) return;
          context.go(AppRoutes.home);
        },
        blockedScreen: () {
          if (!mounted) return;
          context.go(AppRoutes.blocked);
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error('Erro ao checar verificação de e-mail', tag: _tag, error: e, stackTrace: stackTrace);
      if (!mounted) return;
      ToastService.showError(message: e.toString());
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _backToSignIn() async {
    try {
      await firebase_auth.FirebaseAuth.instance.signOut();
    } catch (e, stackTrace) {
      AppLogger.warning('Falha ao fazer signOut ao voltar para login (ignorando)', tag: _tag);
      AppLogger.error('Detalhes signOut', tag: _tag, error: e, stackTrace: stackTrace);
    }

    if (!mounted) return;
    context.go(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final email = _emailToShow;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 8.h),
        Text(
          'Confirmar e-mail',
          style: TextStyles.headerTitle,
        ),
        SizedBox(height: 8.h),
        Text(
          _i18n.translate('email_verification_sent') != ''
              ? _i18n.translate('email_verification_sent')
              : 'Enviamos um e-mail de verificação. Verifique sua caixa de entrada e depois faça login.',
          style: TextStyles.headerSubtitle,
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 16.h),

        GlimpseTextField(
          controller: _emailController,
          labelText: _i18n.translate('email') != '' ? _i18n.translate('email') : 'E-mail',
          hintText: email ?? '',
          readOnly: true,
          enabled: true,
          onTap: () {},
        ),

        SizedBox(height: 12.h),

        // Ações abaixo do input (padrão do fluxo de auth)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _canResend ? _resendVerificationEmail : null,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _canResend
                    ? 'Reenviar'
                    : (_i18n.translate('processing') != ''
                        ? _i18n.translate('processing')
                        : 'Processando'),
                style: TextStyles.navigationLink.copyWith(
                  color: GlimpseColors.primary,
                ),
              ),
            ),
            TextButton(
              onPressed: _backToSignIn,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Voltar ao login',
                style: TextStyles.navigationLink.copyWith(
                  color: GlimpseColors.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final bottomButton = GlimpseButton(
      text: 'Já confirmei, continuar',
      onTap: _isChecking ? null : _checkEmailVerifiedAndContinue,
      backgroundColor: GlimpseColors.primary,
      isProcessing: _isChecking,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AuthAppBar(),
      body: GlimpseSignupLayout(
        header: header,
        content: content,
        bottomButton: bottomButton,
      ),
    );
  }
}
