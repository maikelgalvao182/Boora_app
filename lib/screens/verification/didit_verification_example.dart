import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:partiu/core/services/face_verification_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/verification/didit_verification_screen.dart';
import 'package:permission_handler/permission_handler.dart';

/// Exemplo de como integrar a verificação Didit no fluxo do app
/// 
/// Este exemplo pode ser adaptado para:
/// - Perfil de usuário
/// - Processo de onboarding
/// - Requisito para eventos premium
class DiditVerificationExample extends StatefulWidget {
  const DiditVerificationExample({super.key});

  @override
  State<DiditVerificationExample> createState() =>
      _DiditVerificationExampleState();
}

class _DiditVerificationExampleState extends State<DiditVerificationExample> {
  bool _isVerified = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  Future<void> _checkVerificationStatus() async {
    setState(() => _isLoading = true);
    
    final isVerified = await FaceVerificationService.instance.isUserVerified();
    
    setState(() {
      _isVerified = isVerified;
      _isLoading = false;
    });
  }

  Future<void> _startVerification() async {
    // 1. Verificar e solicitar permissões
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();

    if (!mounted) return;

    if (!cameraStatus.isGranted || !microphoneStatus.isGranted) {
      _showError('camera_microphone_permissions_required');
      return;
    }

    // 2. Navegar para tela de verificação
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const DiditVerificationScreen(),
        fullscreenDialog: true,
      ),
    );

    if (!mounted) return;

    // 3. Processar resultado
    if (result == true) {
      setState(() => _isVerified = true);
      _showSuccess('verification_completed_successfully');
    } else {
      _showError('verification_not_completed');
    }
  }

  void _showSuccess(String message) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(message);
    final displayMessage = translated.isNotEmpty ? translated : message;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMessage),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(String message) {
    final i18n = AppLocalizations.of(context);
    final translated = i18n.translate(message);
    final displayMessage = translated.isNotEmpty ? translated : message;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.translate('identity_verification_title')),
      ),
      body: _isLoading
          ? const Center(
              child: CupertinoActivityIndicator(
                radius: 12,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _isVerified ? Icons.verified_user : Icons.shield_outlined,
                    size: 100,
                    color: _isVerified ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isVerified
                        ? i18n.translate('identity_verified_title')
                        : i18n.translate('identity_not_verified_title'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isVerified
                        ? i18n.translate('identity_verified_description')
                        : i18n.translate('identity_not_verified_description'),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (!_isVerified)
                    ElevatedButton.icon(
                      onPressed: _startVerification,
                      icon: const Icon(Icons.verified_user),
                      label: Text(i18n.translate('verify_identity_button')),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),
                  if (_isVerified) ...[
                    const Divider(height: 40),
                    Text(
                      i18n.translate('verification_benefits_title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBenefit(i18n.translate('verification_benefit_verified_badge')),
                    _buildBenefit(i18n.translate('verification_benefit_more_visibility')),
                    _buildBenefit(i18n.translate('verification_benefit_premium_events')),
                    _buildBenefit(i18n.translate('verification_benefit_more_trust')),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildBenefit(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
