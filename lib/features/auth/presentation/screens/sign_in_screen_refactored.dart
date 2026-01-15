import 'dart:io';

import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/constants/toast_messages.dart';
import 'package:partiu/core/config/dependency_provider.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/models/user_model.dart';
import 'package:partiu/features/auth/presentation/controllers/sign_in_view_model.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/shared/widgets/cached_svg_icon.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class SignInScreenRefactored extends StatefulWidget {
  const SignInScreenRefactored({super.key});

  @override
  SignInScreenRefactoredState createState() => SignInScreenRefactoredState();
}

class SignInScreenRefactoredState extends State<SignInScreenRefactored> {
  // Variables
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late AppLocalizations _i18n;
  late SignInViewModel _viewModel;
  
  // Flags para prevenir cliques duplicados
  bool _isAppleSignInProcessing = false;
  bool _isGoogleSignInProcessing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Obtém o ViewModel através do ServiceLocator
    _viewModel = DependencyProvider.of(context).serviceLocator.get<SignInViewModel>();
  }

  // Handle User Auth
  void _checkUserAccount() {
    /// Auth user account usando o ViewModel
    _viewModel.authUserAccount(
      updateLocationScreen: () {
        // Navega para atualização de localização
        if (!mounted) return;
        context.go(AppRoutes.updateLocation);
      },
      signUpScreen: () {
        // Navega para wizard de cadastro
        if (!mounted) return;
        context.go(AppRoutes.signupWizard);
      },
      homeScreen: () {
        // Navega para home após login bem-sucedido
        if (!mounted) return;
        context.go(AppRoutes.home);
      },
      blockedScreen: () {
        // Navega para tela de conta bloqueada
        if (!mounted) return;
        context.go(AppRoutes.blocked);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    /// Initialization
    _i18n = AppLocalizations.of(context);

    const systemUiStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Android light icons (white)
      statusBarBrightness: Brightness.dark, // iOS light icons (white)
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Configura o estilo da barra de status
      value: systemUiStyle,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: Image.asset(
                'assets/images/capa.jpg',
                fit: BoxFit.cover,
                gaplessPlayback: true, // Evita piscar ao recarregar
                // Placeholder suave enquanto carrega (se ainda não estiver em cache)
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
              ),
            ),
            
            // Content
            SafeArea(
              child: Column(
                children: <Widget>[
                  const Spacer(),
                
                  // Buttons fixed at bottom
                  Column(
                    children: [
                    // Logo
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Image.asset(
                        'assets/images/logo_branca.png',
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ),
                    // Title and subtitle
                    Padding(
                      padding: const EdgeInsets.only(left: 25, right: 25, bottom: 12),
                      child: Text(
                        _i18n.translate('auth_title').isNotEmpty 
                          ? _i18n.translate('auth_title')
                          : 'Where Wedding Dreams\nMeet Reality',
                        style: const TextStyle(
                          fontFamily: FONT_PLUS_JAKARTA_SANS,
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: 0.0,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 4,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 5, bottom: 30),
                      child: Text(
                        _i18n.translate('auth_subtitle').isNotEmpty
                          ? _i18n.translate('auth_subtitle')
                          : 'We connect brides and grooms with nearby vendors through transparent, budget-conscious matchmaking.',
                        style: TextStyles.authSubtitle.copyWith(
                          fontFamily: FONT_PLUS_JAKARTA_SANS,
                          color: Colors.white,
                          fontSize: 16,
                          shadows: [
                            const Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 3,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    /// Sign in with Apple (iOS only)
                    if (Platform.isIOS) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
                        child: GestureDetector(
                          onTap: () async {
                            // Prevenir cliques duplicados
                            if (_isAppleSignInProcessing || _viewModel.isLoading) {
                              return;
                            }
                            
                            setState(() {
                              _isAppleSignInProcessing = true;
                            });
                            
                            try {
                              // Login with Apple usando o ViewModel
                              await _viewModel.signInWithApple(
                              checkUserAccount: _checkUserAccount,
                              onNameReceived: (name) async {
                                await UserModel(userId: "temp").setOAuthDisplayName(name);
                              },
                              onNotAvailable: () {
                                // Show user-friendly message for Apple Sign-In not available
                                ToastService.showError(
                                  message: ToastMessages.appleSignInNotAvailable,
                                );
                              },
                            onError: (error) {
                              // Handle specific Apple Sign-In errors
                              if (error.message?.contains('canceled') == true || 
                                  error.message?.contains('cancelled') == true ||
                                  error.code == 'sign_in_canceled') {
                                // User canceled sign-in
                                final i18n = AppLocalizations.of(context);
                                ToastService.showError(
                                  message: i18n.translate('sign_in_canceled_message'),
                                );
                                } else {
                                  // Other Apple Sign-In errors
                                  ToastService.showError(
                                    message: ToastMessages.signInWithAppleFailed,
                                  );
                                }
                                // Debug
                              },
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isAppleSignInProcessing = false;
                                });
                              }
                            }
                          },
                          child: Container(
                            width: double.maxFinite,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: _isAppleSignInProcessing
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CupertinoActivityIndicator(
                                      color: Colors.black,
                                    ),
                                  )
                                : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CachedSvgIcon(
                                    'assets/icons/apple_icon.svg',
                                    width: 18,
                                    height: 18,
                                    color: Colors.black,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _i18n.translate('sign_in_with_apple').isNotEmpty
                                        ? _i18n.translate('sign_in_with_apple')
                                        : 'Continue with Apple',
                                    style: const TextStyle(
                                      fontFamily: FONT_PLUS_JAKARTA_SANS,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    /// Sign in with Facebook (hidden)
                    const SizedBox.shrink(),
                    const SizedBox(height: 4),
                    /// Sign in with Google
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
                      child: GestureDetector(
                        onTap: () async {
                          // Prevenir cliques duplicados
                          if (_isGoogleSignInProcessing || _viewModel.isLoading) {
                            return;
                          }
                          
                          setState(() {
                            _isGoogleSignInProcessing = true;
                          });
                          
                          try {
                            // Login with Google usando o ViewModel
                            await _viewModel.signInWithGoogle(
                            checkUserAccount: _checkUserAccount,
                            onNameReceived: (name) async {
                              await UserModel(userId: "temp").setOAuthDisplayName(name);
                            },
                            onError: (error) {
                              // Handle specific Google Sign-In errors
                              if (error.message?.contains('canceled') == true || 
                                  error.message?.contains('cancelled') == true ||
                                  error.code == 'sign_in_canceled' ||
                                  error.code == 'network_error') {
                                // User canceled sign-in or network issues
                                final i18n = AppLocalizations.of(context);
                                ToastService.showError(
                                  message: i18n.translate('sign_in_canceled_message'),
                                );
                              } else {
                                // Other Google Sign-In errors
                                ToastService.showError(
                                  message: ToastMessages.signInWithGoogleFailed,
                                );
                              }
                            },
                            );
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isGoogleSignInProcessing = false;
                              });
                            }
                          }
                        },
                        child: Container(
                          width: double.maxFinite,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: _isGoogleSignInProcessing
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CupertinoActivityIndicator(
                                    color: Colors.black,
                                  ),
                                )
                              : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CachedSvgIcon(
                                  'assets/icons/google_icon.svg',
                                  width: 18,
                                  height: 18,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _i18n.translate('sign_in_with_google').isNotEmpty
                                      ? _i18n.translate('sign_in_with_google')
                                      : 'Continue with Google',
                                  style: const TextStyle(
                                    fontFamily: FONT_PLUS_JAKARTA_SANS,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    /// Sign in with Email (outline)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 8, 15, 5),
                      child: SizedBox(
                        width: double.maxFinite,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _viewModel.isLoading
                              ? null
                              : () {
                                  context.push(AppRoutes.emailAuth);
                                },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: Colors.white,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.email_outlined, size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                _i18n.translate('sign_in_with_email').isNotEmpty
                                    ? _i18n.translate('sign_in_with_email')
                                    : 'Continue with Email',
                                style: const TextStyle(
                                  fontFamily: FONT_PLUS_JAKARTA_SANS,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                      ],
                    ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}