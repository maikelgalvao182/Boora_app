import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:partiu/core/models/didit_session.dart';
import 'package:partiu/core/services/didit_verification_service.dart';
import 'package:partiu/core/services/face_verification_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Tela de verificação usando Didit WebView
/// 
/// Esta tela:
/// 1. Cria uma sessão de verificação no Didit
/// 2. Abre a URL da sessão em um WebView
/// 3. Lida com permissões de câmera/microfone
/// 4. Processa o callback de conclusão
/// 5. Salva os resultados da verificação
class DiditVerificationScreen extends StatefulWidget {
  const DiditVerificationScreen({super.key});

  @override
  State<DiditVerificationScreen> createState() =>
      _DiditVerificationScreenState();
}

class _DiditVerificationScreenState extends State<DiditVerificationScreen> {
  static const String _tag = 'DiditVerificationScreen';
  
  WebViewController? _controller;
  
  bool _isLoading = true;
  bool _isPageLoading = true;
  DiditSession? _session;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _createSessionAndLoad();
  }

  /// Cria uma sessão de verificação e carrega no WebView
  Future<void> _createSessionAndLoad() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      if (Platform.isAndroid) {
        final granted = await _ensureAndroidMediaPermissions();
        if (!mounted) return;
        if (!granted) {
          AppLogger.warning(
            'Permissões de câmera/microfone negadas; abortando verificação',
            tag: _tag,
          );
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Permissão de câmera e microfone é necessária para verificar sua identidade.';
          });
          return;
        }
      }

      AppLogger.info('Criando sessão de verificação...', tag: _tag);

      // Cria sessão via serviço
      final session = await DiditVerificationService.instance
          .createVerificationSession();

        if (!mounted) return;

      if (session == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'verification_session_create_failed';
        });
        return;
      }

      AppLogger.info('Sessão criada: ${session.sessionId}', tag: _tag);

      if (mounted) {
        setState(() {
          _session = session;
          _isLoading = false;
        });
      }

      // Configura o WebView com a URL da sessão
      if (!mounted) return;
      _setupWebView(session.url);

      // Inicia observação de mudanças na sessão
      _watchSessionStatus(session.sessionId);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Erro ao criar sessão: $error',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'verification_start_error';
        });
      }
    }
  }

  Future<bool> _ensureAndroidMediaPermissions() async {
    try {
      final result = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final camera = result[Permission.camera];
      final microphone = result[Permission.microphone];

      final hasCamera = camera?.isGranted ?? false;
      final hasMicrophone = microphone?.isGranted ?? false;

      if (hasCamera && hasMicrophone) {
        return true;
      }

      if ((camera?.isPermanentlyDenied ?? false) ||
          (microphone?.isPermanentlyDenied ?? false)) {
        AppLogger.warning(
          'Permissões negadas permanentemente. camera=$camera mic=$microphone',
          tag: _tag,
        );
      } else {
        AppLogger.warning(
          'Permissões negadas/limitadas. camera=$camera mic=$microphone',
          tag: _tag,
        );
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao solicitar permissões no Android: $e',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _setupWebView(String url) {
    // Configure platform-specific parameters
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const {},
          )
        : const PlatformWebViewControllerCreationParams();

    // Initialize the WebView controller (declarar antes para poder referenciar em callbacks)
    final controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            AppLogger.info('Carregando: $url', tag: _tag);
            if (mounted) {
              setState(() {
                _isPageLoading = true;
              });
            }
          },
          onPageFinished: (url) {
            AppLogger.info('Página carregada: $url', tag: _tag);

            // No Android, o WebView pode renderizar um placeholder/overlay de play
            // (principalmente em elementos <video>) antes do stream/câmera iniciar.
            if (Platform.isAndroid) {
              _suppressAndroidPlayOverlay(controller);
            }

            if (mounted) {
              setState(() {
                _isPageLoading = false;
              });
            }
          },
          onWebResourceError: (error) {
            AppLogger.error(
              'Erro ao carregar: ${error.errorCode} - ${error.description}',
              tag: _tag,
            );
            if (mounted) {
              setState(() {
                _isPageLoading = false;
              });
            }
          },
          onNavigationRequest: (request) {
            final url = request.url;
            // Intercepta callback
            if (_isCallbackUrl(url)) {
              _handleCallback(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    controller.loadRequest(Uri.parse(url));

    // Configure platform-specific settings
    final platformController = controller.platform;

    // Android-specific configuration
    if (platformController is AndroidWebViewController) {
      // Mantém o UA customizado só no Android.
      // (No iOS, sobrescrever para UA de Android pode afetar o HTML/fluxo do Didit.)
      controller.setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );

      // Handle permissions
      platformController.setOnPlatformPermissionRequest((request) {
        request.grant();
      });

      // Suporte a <input type="file"> / capture (ex.: abrir câmera para documento)
      platformController.setOnShowFileSelector((params) async {
        try {
          AppLogger.info(
            'File selector solicitado. capture=${params.isCaptureEnabled} mode=${params.mode} types=${params.acceptTypes}',
            tag: _tag,
          );

          final acceptTypes = params.acceptTypes.map((e) => e.toLowerCase()).toList();
          final acceptsImages = acceptTypes.isEmpty || acceptTypes.any((t) => t.contains('image'));

          if (!acceptsImages) {
            AppLogger.warning(
              'File selector com tipos não suportados: ${params.acceptTypes}',
              tag: _tag,
            );
            return <String>[];
          }

          // Garante permissões antes de abrir câmera/galeria.
          final granted = await _ensureAndroidMediaPermissions();
          if (!granted) {
            return <String>[];
          }

          final picker = ImagePicker();

          if (params.isCaptureEnabled) {
            final file = await picker.pickImage(source: ImageSource.camera);
            if (file == null) return <String>[];
            return <String>[file.path];
          }

          // Se não for capture, tenta galeria (single ou múltiplo).
          if (params.mode == FileSelectorMode.openMultiple) {
            final files = await picker.pickMultiImage();
            return files.map((f) => f.path).toList();
          }

          final file = await picker.pickImage(source: ImageSource.gallery);
          if (file == null) return <String>[];
          return <String>[file.path];
        } catch (e, stackTrace) {
          AppLogger.error(
            'Erro no file selector do WebView: $e',
            tag: _tag,
            error: e,
            stackTrace: stackTrace,
          );
          return <String>[];
        }
      });

      platformController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (params) async {
          return const GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          );
        },
        onHidePrompt: () {},
      );
      platformController.setMediaPlaybackRequiresUserGesture(false);
    }

    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }
  }

  Future<void> _suppressAndroidPlayOverlay(WebViewController controller) async {
    try {
      // CSS para esconder overlays/controles de play que aparecem como um ícone grande.
      // Isso é intencionalmente conservador: mira somente pseudo-elementos de controle.
      const css = '''
        video::-webkit-media-controls-start-playback-button { display: none !important; }
        video::-webkit-media-controls-play-button { display: none !important; }
        video::-webkit-media-controls-overlay-play-button { display: none !important; }
        video::-webkit-media-controls { display: none !important; }
      ''';

      final js = '''
        (function() {
          try {
            var style = document.getElementById('__partiu_hide_play_overlay');
            if (!style) {
              style = document.createElement('style');
              style.id = '__partiu_hide_play_overlay';
              style.type = 'text/css';
              style.appendChild(document.createTextNode(${_jsString(css)}));
              (document.head || document.documentElement).appendChild(style);
            }
          } catch (e) {}
        })();
      ''';

      await controller.runJavaScript(js);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Falha ao suprimir overlay de play no Android: $e',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  static String _jsString(String value) {
    // Serializa string Dart para literal JS segura.
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\\'")
        .replaceAll('\n', r'\\n')
        .replaceAll('\r', r'');
    return "'$escaped'";
  }

  /// Observa mudanças no status da sessão
  void _watchSessionStatus(String sessionId) {
    DiditVerificationService.instance
        .watchSession(sessionId)
        .listen((session) {
      if (session == null) return;

      AppLogger.info('Status da sessão: ${session.status}', tag: _tag);

      // Se a verificação foi completada com sucesso
      if ((session.status == 'completed' || session.status == 'Approved') && session.result != null) {
        _handleVerificationSuccess(session.result!);
      } else if (session.status == 'failed' || session.status == 'Rejected' || session.status == 'Failed') {
        _handleVerificationError(session.result);
      }
    });
  }

  /// Processa sucesso da verificação
  Future<void> _handleVerificationSuccess(Map<String, dynamic> result) async {
    AppLogger.info('Verificação concluída com sucesso', tag: _tag);

    try {
      // Salva no FaceVerificationService
      final saved = await FaceVerificationService.instance.saveVerification(
        facialId: result['verification_id'] as String? ?? _session!.sessionId,
        userInfo: result,
      );

      if (saved) {
        AppLogger.info('Dados de verificação salvos', tag: _tag);
        
        if (mounted) {
          // Fecha a tela e retorna sucesso
          Navigator.of(context).pop(true);
        }
      } else {
        AppLogger.error('Erro ao salvar verificação', tag: _tag);
        if (mounted) {
          _showError('verification_save_error');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao processar verificação: $e',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      
      if (mounted) {
        _showError('error_processing_verification');
      }
    }
  }

  /// Processa erro na verificação
  void _handleVerificationError(Map<String, dynamic>? result) {
    final errorMessage = result?['error'] as String? ?? 'verification_error_default';
    AppLogger.error('Verificação falhou: $errorMessage', tag: _tag);
    
    if (mounted) {
      _showError(errorMessage);
    }
  }

  /// Mostra mensagem de erro
  void _showError(String message) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(message);
    final displayMessage = translated.isNotEmpty ? translated : message;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMessage),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(i18n.translate('identity_verification_title')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _buildError();
    }

    if (_isLoading || _session == null) {
      return _buildLoading();
    }

    return _buildWebView();
  }

  /// Constrói o loading
  Widget _buildLoading() {
    final i18n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CupertinoActivityIndicator(
            color: Colors.white,
            radius: 12,
          ),
          const SizedBox(height: 16),
          Text(
            i18n.translate('verification_preparing'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói a mensagem de erro
  Widget _buildError() {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(_errorMessage!);
    final displayMessage = translated.isNotEmpty ? translated : _errorMessage!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              displayMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _createSessionAndLoad,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: Text(i18n.translate('try_again')),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói o WebView
  Widget _buildWebView() {
    if (_controller == null) {
      return _buildLoading();
    }

    // No Android, evita mostrar o HTML inicial (onde o ícone/asset de play aparece)
    // enquanto a página ainda está carregando.
    if (Platform.isAndroid && _isPageLoading) {
      return _buildLoading();
    }

    return WebViewWidget(controller: _controller!);
  }

  /// Verifica se é URL de callback
  bool _isCallbackUrl(String url) {
    // Ajuste conforme sua URL de callback configurada
    return url.contains('/verification/callback') || 
           url.contains('partiu.app/callback');
  }

  /// Processa callback
  Future<void> _handleCallback(String url) async {
    AppLogger.info('Callback recebido: $url', tag: _tag);

    try {
      final uri = Uri.parse(url);
      final sessionId = uri.queryParameters['verificationSessionId'] ?? 
                       uri.queryParameters['session_id'] ?? 
                       uri.queryParameters['sessionId'];

      if (sessionId == null) {
        AppLogger.warning('Session ID não encontrado no callback', tag: _tag);
        return;
      }

      // O status da sessão já é observado via watchSession
      // Apenas loga o callback recebido
      AppLogger.info('Callback processado para sessão: $sessionId', tag: _tag);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro ao processar callback: $e',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    // _controller não precisa de dispose explícito
    super.dispose();
  }
}
