import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/constants/toast_messages.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_signup_layout.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/shared/widgets/auth_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
  as firebase_auth_platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Tela de recuperação de senha
/// Permite que o usuário receba um link de redefinição de senha via email
/// Seguindo o padrão de UI da EmailAuthScreen
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  
  bool _isLoading = false;
  late AppLocalizations _i18n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _i18n = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _maskEmailForLogs(String email) {
    final trimmed = email.trim();
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 1) return '***';

    final local = trimmed.substring(0, atIndex);
    final domain = trimmed.substring(atIndex + 1);
    final localMasked = '${local[0]}***';
    return '$localMasked@$domain';
  }

  Future<void> _sendPasswordResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      AppLogger.info(
        'Solicitando recuperação de senha para: ${_maskEmailForLogs(email)}',
        tag: 'FORGOT_PASSWORD',
      );

      // ✅ Diagnóstico: se a conta existe mas NÃO tem provider password,
      // não há senha para resetar (ex.: login via Google/Apple).
        final methods = await firebase_auth_platform.FirebaseAuthPlatform.instance
          .fetchSignInMethodsForEmail(email);
      final hasPasswordProvider = methods.contains('password');

      if (methods.isNotEmpty && !hasPasswordProvider) {
        final providers = methods.join(', ');
        AppLogger.warning(
          'E-mail não tem provider password. Métodos: $providers',
          tag: 'FORGOT_PASSWORD',
        );

        if (mounted) {
          setState(() => _isLoading = false);

          ToastService.showWarning(
            message: _i18n.translate('email_linked_to_social_login').isNotEmpty
                ? _i18n.translate('email_linked_to_social_login')
                : _i18n.translate('account_uses_social_login'),
          );
        }
        return;
      }
      
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );
      
      AppLogger.success('Email de recuperação enviado com sucesso', tag: 'FORGOT_PASSWORD');

      if (mounted) {
        setState(() => _isLoading = false);
        
        // Mostra sucesso com toast
        ToastService.showSuccess(
          message: _i18n.translate('password_reset_link_sent') != '' 
              ? _i18n.translate('password_reset_link_sent')
              : ToastMessages.passwordResetLinkSent,
        );
        
        // Aguarda um pouco para o usuário ver a mensagem antes de voltar
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          context.pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      AppLogger.error('Erro no Firebase Auth ao enviar email de recuperação: ${e.code}', tag: 'FORGOT_PASSWORD');
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        var message = '';
        if (e.code == 'user-not-found') {
          message = _i18n.translate('email_not_found') != '' 
              ? _i18n.translate('email_not_found')
              : 'No user found with this email address.';
        } else if (e.code == 'invalid-email') {
          message = _i18n.translate('invalid_email_format') != '' 
              ? _i18n.translate('invalid_email_format')
              : 'The email address is not valid.';
        } else if (e.code == 'too-many-requests') {
          message = _i18n.translate('too_many_requests') != '' 
              ? _i18n.translate('too_many_requests')
              : 'Too many requests. Please try again later.';
        } else {
          message = e.message ?? e.code;
        }

        ToastService.showError(
          message: message,
        );
      }
    } catch (e) {
      AppLogger.error('Erro inesperado ao enviar email de recuperação: $e', tag: 'FORGOT_PASSWORD');
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        ToastService.showError(
          message: _i18n.translate('something_went_wrong') != '' 
              ? _i18n.translate('something_went_wrong')
              : ToastMessages.somethingWentWrong,
        );
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return _i18n.translate('please_enter_email') != '' 
          ? _i18n.translate('please_enter_email')
          : 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return _i18n.translate('please_enter_valid_email') != '' 
          ? _i18n.translate('please_enter_valid_email')
          : 'Please enter a valid email';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Cabeçalho simples sem barra de progresso
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          _i18n.translate('forgot_password') != '' 
              ? _i18n.translate('forgot_password')
              : 'Forgot Password?',
          style: TextStyles.headerTitle,
        ),
        const SizedBox(height: 8),
        Text(
          _i18n.translate('forgot_password_description') != '' 
              ? _i18n.translate('forgot_password_description')
              : "Enter your email and we'll send you a link to reset your password",
          style: TextStyles.headerSubtitle,
        ),
      ],
    );

    // Conteúdo do formulário seguindo o padrão da EmailAuthScreen
    final content = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // Campo de Email
          GlimpseTextField(
            controller: _emailController,
            labelText: _i18n.translate('email'),
            hintText: _i18n.translate('please_enter_your_email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: _validateEmail,
          ),
          const SizedBox(height: 12),

          // Link para voltar ao login
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _i18n.translate('remember_password') != '' 
                    ? _i18n.translate('remember_password')
                    : 'Remember your password?',
                style: TextStyles.navigationText,
              ),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  _i18n.translate('back_to_sign_in') != '' 
                      ? _i18n.translate('back_to_sign_in')
                      : 'Back to Sign In',
                  style: TextStyles.navigationLink.copyWith(
                    color: GlimpseColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Botão de Submit seguindo o padrão da EmailAuthScreen
    final bottomButton = GlimpseButton(
      text: _i18n.translate('send_reset_link') != '' 
          ? _i18n.translate('send_reset_link')
          : 'Send Reset Link',
      onTap: _isLoading ? null : _sendPasswordResetEmail,
      backgroundColor: GlimpseColors.primary,
      isProcessing: _isLoading,
    );

    // Layout completo seguindo o padrão da EmailAuthScreen
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: const AuthAppBar(),
        body: GlimpseSignupLayout(
          header: header,
          content: content,
          bottomButton: bottomButton,
        ),
      ),
    );
  }
}
