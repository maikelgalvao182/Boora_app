import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 🚩 Serviço profissional de denúncias
/// 
/// Inspirado em apps como Instagram, Tinder, TikTok
/// - Baixo custo
/// - Estrutura limpa
/// - Fácil auditoria
/// - Escalável
class ReportService {
  static final ReportService instance = ReportService._internal();
  ReportService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  static const String _appVersion = '1.0.0';
  static const String _platform = 'flutter';

  /// Envia uma denúncia para a coleção 'reports'
  /// 
  /// [message] - Mensagem obrigatória da denúncia
  /// [targetUserId] - ID do usuário denunciado (opcional)
  /// [eventId] - ID do evento relacionado (opcional)
  Future<void> sendReport({
    required String message,
    String? targetUserId,
    String? eventId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception("Usuário não autenticado");
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw Exception("Mensagem não pode estar vazia");
    }

    if (trimmedMessage.length > 2000) {
      throw Exception("Mensagem muito longa (máximo 2000 caracteres)");
    }

    try {
      // Buscar activityText se for denúncia de evento
      String? activityText;
      if (eventId != null) {
        try {
          final eventDoc = await _firestore.collection('events').doc(eventId).get();
          if (eventDoc.exists) {
            final eventData = eventDoc.data();
            activityText = eventData?['activityText'] as String?;
          }
        } catch (e) {
          debugPrint('⚠️ [ReportService] Erro ao buscar activityText: $e');
          // Continua mesmo se falhar ao buscar o activityText
        }
      }

      final reportData = {
        'reporterId': user.uid,
        'targetUserId': targetUserId,
        'eventId': eventId,
        'message': trimmedMessage,
        'createdAt': FieldValue.serverTimestamp(),
        'platform': _platform,
        'appVersion': _appVersion,
        if (activityText != null) 'activityText': activityText,
      };

      await _firestore.collection('reports').add(reportData);

      debugPrint('✅ [ReportService] Denúncia enviada com sucesso');
    } catch (e) {
      debugPrint('❌ [ReportService] Erro ao enviar denúncia: $e');
      rethrow;
    }
  }

  /// Envia denúncia de usuário
  Future<void> reportUser({
    required String targetUserId,
    required String message,
  }) async {
    return sendReport(
      message: message,
      targetUserId: targetUserId,
    );
  }

  /// Envia denúncia de evento
  Future<void> reportEvent({
    required String eventId,
    required String message,
  }) async {
    return sendReport(
      message: message,
      eventId: eventId,
    );
  }

  /// Envia denúncia genérica (sem contexto específico)
  Future<void> reportGeneral({
    required String message,
  }) async {
    return sendReport(message: message);
  }
}
