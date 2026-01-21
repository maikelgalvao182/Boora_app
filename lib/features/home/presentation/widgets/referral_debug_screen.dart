import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/services/referral_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Tela de debug para testar o sistema de referral
/// 
/// Uso: Adicione ao router ou abra via Navigator.push
class ReferralDebugScreen extends StatefulWidget {
  const ReferralDebugScreen({super.key});

  @override
  State<ReferralDebugScreen> createState() => _ReferralDebugScreenState();
}

class _ReferralDebugScreenState extends State<ReferralDebugScreen> {
  final _testReferrerIdController = TextEditingController(text: 'TEST_USER_ID');
  String _logs = '';
  
  @override
  void dispose() {
    _testReferrerIdController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _logs = '[$timestamp] $message\n$_logs';
    });
    AppLogger.info(message, tag: 'REFERRAL_DEBUG');
  }

  Future<void> _testGenerateLink() async {
    _addLog('🔗 Testando geração de link...');
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _addLog('❌ Usuário não logado');
      return;
    }

    try {
      final link = await ReferralService.instance.generateInviteLinkAsync(
        referrerId: userId,
        referrerName: 'Test User',
      );
      
      if (link != null) {
        _addLog('✅ Link gerado: $link');
        await Clipboard.setData(ClipboardData(text: link));
        _addLog('📋 Link copiado para área de transferência');
      } else {
        _addLog('❌ Falha ao gerar link');
      }
    } catch (e) {
      _addLog('❌ Erro: $e');
    }
  }

  Future<void> _testCaptureReferral() async {
    _addLog('📥 Testando captura de referral...');
    
    final referrerId = _testReferrerIdController.text.trim();
    if (referrerId.isEmpty) {
      _addLog('❌ ReferrerId vazio');
      return;
    }

    try {
      await ReferralService.instance.captureReferral(
        referrerId: referrerId,
        deepLinkValue: 'invite',
      );
      _addLog('✅ Referral capturado: $referrerId');
    } catch (e) {
      _addLog('❌ Erro: $e');
    }
  }

  Future<void> _testCheckPendingReferral() async {
    _addLog('🔍 Verificando referral pendente...');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingReferrerId = prefs.getString('pending_referrer_id');
      
      if (pendingReferrerId != null) {
        _addLog('✅ Referral pendente encontrado: $pendingReferrerId');
      } else {
        _addLog('⚠️ Nenhum referral pendente');
      }
    } catch (e) {
      _addLog('❌ Erro: $e');
    }
  }

  Future<void> _testConsumePendingReferral() async {
    _addLog('📤 Testando consumo de referral pendente...');
    
    try {
      final referrerId = await ReferralService.instance.consumePendingReferrerId();
      
      if (referrerId != null) {
        _addLog('✅ Referral consumido: $referrerId');
      } else {
        _addLog('⚠️ Nenhum referral pendente para consumir');
      }
    } catch (e) {
      _addLog('❌ Erro: $e');
    }
  }

  Future<void> _testClearPendingReferral() async {
    _addLog('🗑️ Limpando referral pendente...');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_referrer_id');
      await prefs.remove('pending_deep_link_value');
      await prefs.remove('pending_referral_captured_at');
      
      _addLog('✅ Referral pendente limpo');
    } catch (e) {
      _addLog('❌ Erro: $e');
    }
  }

  Future<void> _testCheckFirestoreData() async {
    _addLog('🔍 Verificando dados do Firestore...');
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _addLog('❌ Usuário não logado');
      return;
    }

    try {
      // Verificar documento do usuário
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final referralCount = data?['referralInstallCount'] ?? 0;
        final referrerId = data?['referrerId'];
        
        _addLog('✅ User doc encontrado');
        _addLog('   - referralInstallCount: $referralCount');
        _addLog('   - referrerId: ${referrerId ?? "null"}');
      } else {
        _addLog('❌ User doc não encontrado');
      }

      // Verificar ReferralInstalls
      final referralInstalls = await FirebaseFirestore.instance
          .collection('ReferralInstalls')
          .where('referrerId', isEqualTo: userId)
          .get();

      _addLog('✅ ReferralInstalls: ${referralInstalls.docs.length} docs');
      
      for (final doc in referralInstalls.docs) {
        final data = doc.data();
        _addLog('   - userId: ${data["userId"]}');
        _addLog('     createdAt: ${(data["createdAt"] as Timestamp?)?.toDate()}');
      }
    } catch (e) {
      _addLog('❌ Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Referral Debug',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Input para testar referrerId customizado
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _testReferrerIdController,
              decoration: InputDecoration(
                labelText: 'Test ReferrerId',
                border: const OutlineInputBorder(),
                labelStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS),
              ),
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS),
            ),
          ),
          
          // Botões de teste
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _testGenerateLink,
                  child: const Text('Gerar Link'),
                ),
                ElevatedButton(
                  onPressed: _testCaptureReferral,
                  child: const Text('Capturar Referral'),
                ),
                ElevatedButton(
                  onPressed: _testCheckPendingReferral,
                  child: const Text('Verificar Pendente'),
                ),
                ElevatedButton(
                  onPressed: _testConsumePendingReferral,
                  child: const Text('Consumir Pendente'),
                ),
                ElevatedButton(
                  onPressed: _testClearPendingReferral,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Limpar Pendente'),
                ),
                ElevatedButton(
                  onPressed: _testCheckFirestoreData,
                  child: const Text('Verificar Firestore'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _logs = '';
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Limpar Logs'),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Logs
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _logs.isEmpty ? 'Nenhum log ainda...' : _logs,
                  style: GoogleFonts.getFont(
                    'Roboto Mono',
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
