import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/constants/toast_messages.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_signup_layout.dart';
import 'package:partiu/shared/services/toast_service.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  Future<void> _sendPasswordResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      AppLogger.info('Enviando email de recuperação de senha para: ${_emailController.text.trim()}', tag: 'FORGOT_PASSWORD');
      
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      
      AppLogger.success('Email de recuperação enviado com sucesso', tag: 'FORGOT_PASSWORD');

      if (mounted) {
        setState(() => _isLoading = false);
        
        // Mostra sucesso com toast
        ToastService.showSuccess(
          context: context,
          title: _i18n.translate('success') != '' 
              ? _i18n.translate('success')
              : ToastMessages.passwordResetSuccess,
          subtitle: _i18n.translate('password_reset_link_sent') != '' 
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
          context: context,
          title: _i18n.translate('error') != '' 
              ? _i18n.translate('error')
              : ToastMessages.error,
          subtitle: message,
        );
      }
    } catch (e) {
      AppLogger.error('Erro inesperado ao enviar email de recuperação: $e', tag: 'FORGOT_PASSWORD');
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        ToastService.showError(
          context: context,
          title: ToastMessages.error,
          subtitle: _i18n.translate('something_went_wrong') != '' 
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
          const SizedBox(height: 15),

          // Campo de Email
          GlimpseTextField(
            controller: _emailController,
            labelText: _i18n.translate('email'),
            hintText: _i18n.translate('please_enter_your_email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: _validateEmail,
          ),
          const SizedBox(height: 24),

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
                  style: TextStyles.navigationLink,
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
      backgroundColor: GlimpseColors.primaryColorLight,
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
        backgroundColor: GlimpseColors.textSubTitle,
        appBar: AppBar(
          backgroundColor: GlimpseColors.textSubTitle,
          elevation: 0,
          leading: GlimpseBackButton.iconButton(
            onPressed: () => context.pop(),
            color: Colors.black,
          ),
          centerTitle: true,
          title: SvgPicture.asset(
            'assets/svg/logo_preta.svg',
            height: 24,
          ),
        ),
        body: GlimpseSignupLayout(
          header: header,
          content: content,
          bottomButton: bottomButton,
        ),
      ),
    );
  }
}
