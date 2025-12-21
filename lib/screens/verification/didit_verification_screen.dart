import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:partiu/core/models/didit_session.dart';
import 'package:partiu/core/services/didit_verification_service.dart';
import 'package:partiu/core/services/face_verification_service.dart';
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

      AppLogger.info('Criando sessão de verificação...', tag: _tag);

      // Cria sessão via serviço
      final session = await DiditVerificationService.instance
          .createVerificationSession();

      if (session == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível criar sessão de verificação';
        });
        return;
      }

      AppLogger.info('Sessão criada: ${session.sessionId}', tag: _tag);

      setState(() {
        _session = session;
        _isLoading = false;
      });

      // Configura o WebView com a URL da sessão
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
      
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao iniciar verificação: $error';
      });
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

    // Initialize the WebView controller
    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            AppLogger.info('Carregando: $url', tag: _tag);
          },
          onPageFinished: (url) {
            AppLogger.info('Página carregada: $url', tag: _tag);
          },
          onWebResourceError: (error) {
            AppLogger.error(
              'Erro ao carregar: ${error.errorCode} - ${error.description}',
              tag: _tag,
            );
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
      )
      ..loadRequest(Uri.parse(url));

    // Configure platform-specific settings
    final platformController = controller.platform;

    // Android-specific configuration
    if (platformController is AndroidWebViewController) {
      // Handle permissions
      platformController.setOnPlatformPermissionRequest((request) {
        request.grant();
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

    setState(() {
      _controller = controller;
    });
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
    final errorMessage = result?['error'] as String? ?? 'Erro na verificação';
    AppLogger.error('Verificação falhou: $errorMessage', tag: _tag);
    
    if (mounted) {
      _showError(errorMessage);
    }
  }

  /// Mostra mensagem de erro
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Verificação de Identidade'),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Colors.white,
          ),
          SizedBox(height: 16),
          Text(
            'Preparando verificação...',
            style: TextStyle(
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
              _errorMessage!,
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
              child: const Text('Tentar Novamente'),
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
