import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/auth/presentation/controllers/email_auth_view_model.dart';
import 'package:partiu/features/auth/presentation/controllers/sign_in_view_model.dart';
import 'package:partiu/shared/widgets/glimpse_signup_layout.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/validators/auth_validators.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/shared/widgets/auth_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:partiu/shared/widgets/terms_and_privacy_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Tela de autenticação com Email/Senha
/// Permite tanto LOGIN quanto CADASTRO com Firebase Auth Email
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late AppLocalizations _i18n;
  late SignInViewModel _signInViewModel;
  late EmailAuthViewModel _emailAuthViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _i18n = AppLocalizations.of(context);
    
    final serviceLocator = DependencyProvider.of(context).serviceLocator;
    _signInViewModel = serviceLocator.get<SignInViewModel>();
    _emailAuthViewModel = serviceLocator.get<EmailAuthViewModel>();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Handle User Auth - chama o fluxo de verificação de conta
  void _checkUserAccount() {
    _signInViewModel.authUserAccount(
      updateLocationScreen: () {
        if (!mounted) return;
        context.go(AppRoutes.updateLocation);
      },
      signUpScreen: () {
        // Reset loading state before navigation
        _emailAuthViewModel.setLoading(false);
        // Navega para próxima tela (cadastro)
        if (!mounted) return;
        context.push(AppRoutes.signupWizard);
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
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    _emailAuthViewModel.setLoading(true);

    if (_emailAuthViewModel.isLogin) {
      await _handleLogin();
    } else {
      await _handleSignUp();
    }
  }

  Future<void> _handleLogin() async {
    final currentContext = context;
    try {
      await _signInViewModel.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        checkUserAccount: _checkUserAccount,
        onError: (error) {
          _emailAuthViewModel.setLoading(false);
          if (!currentContext.mounted) return;
          _showAuthError(currentContext, error, isLogin: true);
        },
      );
    } catch (e) {
      _emailAuthViewModel.setLoading(false);
      if (currentContext.mounted) {
        ToastService.showError(
          message: e.toString(),
        );
      }
    }
  }

  Future<void> _handleSignUp() async {
    final currentContext = context;
    try {
      await _signInViewModel.createUserWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        checkUserAccount: _checkUserAccount,
        onError: (error) {
          _emailAuthViewModel.setLoading(false);
          if (!currentContext.mounted) return;
          _showAuthError(currentContext, error, isLogin: false);
        },
      );
    } catch (e) {
      _emailAuthViewModel.setLoading(false);
      if (currentContext.mounted) {
        ToastService.showError(
          message: e.toString(),
        );
      }
    }
  }

  /// Centraliza tratamento de erros de autenticação
  void _showAuthError(BuildContext context, dynamic error, {required bool isLogin}) {
    var message = '';

    // Fluxos especiais: verificação de e-mail (não é erro técnico)
    if (error != null && error.code == 'email_verification_sent') {
      message = _i18n.translate('email_verification_sent');
      ToastService.showInfo(message: message);

      // Após cadastro, direciona para tela dedicada de verificação
      // (e deixa o modo em Login para quando voltar)
      if (!_emailAuthViewModel.isLogin) {
        _emailAuthViewModel.toggleMode();
      }
      _passwordController.clear();

      context.push(
        AppRoutes.emailVerification,
        extra: {
          'email': _emailController.text.trim(),
        },
      );
      return;
    }

    if (error != null && error.code == 'email_not_verified') {
      message = _i18n.translate('email_not_verified');
      ToastService.showWarning(message: message);

      _passwordController.clear();
      context.push(
        AppRoutes.emailVerification,
        extra: {
          'email': _emailController.text.trim(),
        },
      );
      return;
    }
    
    if (isLogin) {
      // Erros de Login
      if (error.code == 'INVALID_LOGIN_CREDENTIALS' || 
          error.code == 'invalid-credential' ||
          error.code == 'wrong-password' ||
          error.code == 'user-not-found') {
        message = _i18n.translate('invalid_login_credentials');
      } else if (error.code == 'user-disabled') {
        message = _i18n.translate('user_disabled');
      } else if (error.code == 'too-many-requests') {
        message = _i18n.translate('too_many_requests');
      } else {
        message = error.message?.toString() ?? error.code.toString();
      }
    } else {
      // Erros de Cadastro
      if (error.code == 'weak-password') {
        message = _i18n.translate('weak_password');
      } else if (error.code == 'email-already-in-use') {
        message = _i18n.translate('email_already_in_use');
      } else if (error.code == 'invalid-email') {
        message = _i18n.translate('invalid_email');
      } else {
        message = error.message?.toString() ?? error.code.toString();
      }
    }

    ToastService.showError(
      message: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _emailAuthViewModel,
      child: Consumer<EmailAuthViewModel>(
        builder: (context, viewModel, child) {
          // Cabeçalho simples sem barra de progresso
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                viewModel.isLogin 
                    ? _i18n.translate('sign_in_title')
                    : _i18n.translate('create_account'),
                style: TextStyles.headerTitle,
              ),
              const SizedBox(height: 8),
              Text(
                viewModel.isLogin
                    ? _i18n.translate('enter_your_credentials_to_continue')
                    : _i18n.translate('fill_the_form_to_create_account'),
                style: TextStyles.headerSubtitle,
              ),
            ],
          );

          // Conteúdo do formulário
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
                  textInputAction: TextInputAction.next,
                  validator: (value) => AuthValidators.validateEmail(
                    value,
                    translate: _i18n.translate,
                  ),
                ),
                const SizedBox(height: 16),

                // Campo de Senha
                GlimpseTextField(
                  controller: _passwordController,
                  labelText: _i18n.translate('password'),
                  hintText: _i18n.translate('please_enter_password'),
                  obscureText: viewModel.obscurePassword,
                  textInputAction: TextInputAction.done,
                  validator: (value) => AuthValidators.validatePassword(
                    value, 
                    isSignUp: !viewModel.isLogin,
                    translate: _i18n.translate,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      viewModel.obscurePassword ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
                      color: GlimpseColors.textSubTitle,
                    ),
                    onPressed: viewModel.togglePasswordVisibility,
                  ),
                ),
                const SizedBox(height: 12),

                // Links na mesma linha: "Criar conta" e "Esqueceu senha?" (apenas no modo login)
                if (viewModel.isLogin)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Link "Criar conta"
                      TextButton(
                        onPressed: () {
                          viewModel.toggleMode();
                          _formKey.currentState?.reset();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _i18n.translate('sign_up'),
                          style: TextStyles.navigationLink.copyWith(
                            color: GlimpseColors.primary,
                          ),
                        ),
                      ),
                      // Link "Esqueceu a senha?"
                      TextButton(
                        onPressed: () {
                          context.push(AppRoutes.forgotPassword);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _i18n.translate('forgot_password'),
                          style: TextStyles.actionLink,
                        ),
                      ),
                    ],
                  ),

                // Toggle entre Login e Cadastro (apenas no modo cadastro)
                if (!viewModel.isLogin)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _i18n.translate('already_have_account'),
                        style: TextStyles.navigationText,
                      ),
                      TextButton(
                        onPressed: () {
                          viewModel.toggleMode();
                          _formKey.currentState?.reset();
                        },
                        child: Text(
                          _i18n.translate('sign_in'),
                          style: TextStyles.navigationLink.copyWith(
                            color: GlimpseColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),
              ],
            ),
          );

          // Botão de Submit (desabilitado durante loading)
          final bottomButton = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlimpseButton(
                text: viewModel.isLogin
                    ? _i18n.translate('sign_in')
                    : _i18n.translate('create_account'),
                onTap: viewModel.isLoading ? null : _submit,
                backgroundColor: GlimpseColors.primary,
                isProcessing: viewModel.isLoading,
              ),
              if (!viewModel.isLogin)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TermsAndPrivacyLinks(
                    prefixText: _i18n
                        .translate('agree_terms_and_privacy_prefix'),
                    suffixText: _i18n
                        .translate('agree_terms_and_privacy_suffix'),
                    termsTextKey: 'terms_of_service',
                    privacyTextKey: 'privacy_policy',
                  ),
                ),
            ],
          );

          // Layout completo com fundo branco e ícones da barra de status pretos
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark, // Ícones pretos
              statusBarBrightness: Brightness.light, // iOS
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
        },
      ),
    );
  }
}
