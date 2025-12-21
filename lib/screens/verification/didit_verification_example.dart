import 'package:flutter/material.dart';
import 'package:partiu/core/services/face_verification_service.dart';
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

    // 3. Processar resultado
    if (result == true) {
      setState(() => _isVerified = true);
      _showSuccess('verification_completed_successfully');
    } else {
      _showError('verification_not_completed');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificação de Identidade'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                        ? 'Perfil Verificado'
                        : 'Perfil Não Verificado',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isVerified
                        ? 'Sua identidade foi verificada com sucesso. Você tem acesso a todos os recursos premium do app.'
                        : 'Verifique sua identidade para garantir segurança e acessar recursos premium.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (!_isVerified)
                    ElevatedButton.icon(
                      onPressed: _startVerification,
                      icon: const Icon(Icons.verified_user),
                      label: const Text('Verificar Identidade'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),
                  if (_isVerified) ...[
                    const Divider(height: 40),
                    const Text(
                      'Benefícios da Verificação:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBenefit('Selo de perfil verificado'),
                    _buildBenefit('Maior visibilidade'),
                    _buildBenefit('Acesso a eventos premium'),
                    _buildBenefit('Maior confiança dos usuários'),
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
