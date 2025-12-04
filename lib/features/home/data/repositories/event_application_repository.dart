import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// Repositório para gerenciar aplicações de usuários em eventos
class EventApplicationRepository {
  final FirebaseFirestore _firestore;
  final UserRepository _userRepo;

  EventApplicationRepository({
    FirebaseFirestore? firestore,
    UserRepository? userRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _userRepo = userRepository ?? UserRepository(firestore);

  /// Cria uma nova aplicação para um evento
  /// 
  /// O status é determinado automaticamente baseado no privacyType do evento:
  /// - "open" → autoApproved
  /// - "private" → pending
  Future<String> createApplication({
    required String eventId,
    required String userId,
    required String eventPrivacyType,
  }) async {
    // Determinar status baseado no tipo de privacidade
    final status = eventPrivacyType == 'open' 
        ? ApplicationStatus.autoApproved 
        : ApplicationStatus.pending;

    final now = DateTime.now();
    
    final application = EventApplicationModel(
      id: '', // Será gerado pelo Firestore
      eventId: eventId,
      userId: userId,
      status: status,
      appliedAt: now,
      decisionAt: status == ApplicationStatus.autoApproved ? now : null,
    );

    try {
      final docRef = await _firestore
          .collection('EventApplications')
          .add(application.toFirestore());

      debugPrint('✅ Aplicação criada: ${docRef.id} (status: ${status.value})');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Erro ao criar aplicação: $e');
      rethrow;
    }
  }

  /// Busca aplicação de um usuário para um evento específico
  Future<EventApplicationModel?> getUserApplication({
    required String eventId,
    required String userId,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return EventApplicationModel.fromFirestore(querySnapshot.docs.first);
    } catch (e) {
      debugPrint('❌ Erro ao buscar aplicação: $e');
      return null;
    }
  }

  /// Verifica se usuário já aplicou para um evento
  Future<bool> hasUserApplied({
    required String eventId,
    required String userId,
  }) async {
    final application = await getUserApplication(
      eventId: eventId,
      userId: userId,
    );
    return application != null;
  }

  /// Aprova uma aplicação (apenas para eventos privados, apenas pelo criador)
  Future<void> approveApplication(String applicationId) async {
    try {
      await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .update({
        'status': ApplicationStatus.approved.value,
        'decisionAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Aplicação aprovada: $applicationId');
    } catch (e) {
      debugPrint('❌ Erro ao aprovar aplicação: $e');
      rethrow;
    }
  }

  /// Rejeita uma aplicação (apenas para eventos privados, apenas pelo criador)
  Future<void> rejectApplication(String applicationId) async {
    try {
      await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .update({
        'status': ApplicationStatus.rejected.value,
        'decisionAt': FieldValue.serverTimestamp(),
      });

      debugPrint('❌ Aplicação rejeitada: $applicationId');
    } catch (e) {
      debugPrint('❌ Erro ao rejeitar aplicação: $e');
      rethrow;
    }
  }

  /// Lista todas as aplicações para um evento (para o organizador)
  Future<List<EventApplicationModel>> getEventApplications(String eventId) async {
    try {
      final querySnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .orderBy('appliedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => EventApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar aplicações: $e');
      return [];
    }
  }

  /// Lista aplicações pendentes de um evento
  Future<List<EventApplicationModel>> getPendingApplications(String eventId) async {
    try {
      final querySnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: ApplicationStatus.pending.value)
          .orderBy('appliedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => EventApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar aplicações pendentes: $e');
      return [];
    }
  }

  /// Busca aplicações aprovadas com dados dos usuários (photoUrl + fullName)
  /// 
  /// Retorna Map com:
  /// - userId
  /// - photoUrl
  /// - fullName
  /// - appliedAt
  Future<List<Map<String, dynamic>>> getApprovedApplicationsWithUserData(String eventId) async {
    try {
      // 1. Buscar applications aprovadas ou auto-aprovadas
      final applicationsSnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', whereIn: [
            ApplicationStatus.approved.value,
            ApplicationStatus.autoApproved.value,
          ])
          .orderBy('appliedAt', descending: false) // Ordem cronológica
          .get();

      if (applicationsSnapshot.docs.isEmpty) {
        return [];
      }

      // 2. Extrair userIds e buscar em batch (otimizado)
      final userIds = applicationsSnapshot.docs
          .map((doc) => doc.data()['userId'] as String)
          .toList();

      final usersBasicInfo = await _userRepo.getUsersBasicInfo(userIds);
      
      // 3. Criar mapa userId → userData para lookup rápido
      final userDataMap = {
        for (var user in usersBasicInfo) user['userId'] as String: user
      };

      // 4. Combinar applications com user data
      final results = <Map<String, dynamic>>[];
      
      for (final appDoc in applicationsSnapshot.docs) {
        final appData = appDoc.data();
        final userId = appData['userId'] as String;
        final userData = userDataMap[userId];
        
        if (userData != null) {
          results.add({
            'userId': userId,
            'photoUrl': userData['photoUrl'] as String?,
            'fullName': userData['fullName'] as String?,
            'appliedAt': appData['appliedAt'] as Timestamp?,
          });
        }
      }

      return results;
    } catch (e) {
      debugPrint('❌ Erro ao buscar aplicações aprovadas com user data: $e');
      return [];
    }
  }

  /// Busca as aplicações mais recentes com dados dos usuários (limitado)
  /// 
  /// Útil para exibir preview de participantes em cards/listas
  /// 
  /// Retorna Map com:
  /// - userId
  /// - photoUrl
  /// - fullName
  /// - appliedAt
  Future<List<Map<String, dynamic>>> getRecentApplicationsWithUserData(
    String eventId, {
    int limit = 5,
  }) async {
    try {
      // 1. Buscar applications aprovadas ou auto-aprovadas (limitado)
      final applicationsSnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', whereIn: [
            ApplicationStatus.approved.value,
            ApplicationStatus.autoApproved.value,
          ])
          .orderBy('appliedAt', descending: false) // Mais antigos primeiro
          .limit(limit)
          .get();

      if (applicationsSnapshot.docs.isEmpty) {
        return [];
      }

      // 2. Extrair userIds e buscar em batch (otimizado)
      final userIds = applicationsSnapshot.docs
          .map((doc) => doc.data()['userId'] as String)
          .toList();

      final usersBasicInfo = await _userRepo.getUsersBasicInfo(userIds);
      
      // 3. Criar mapa userId → userData para lookup rápido
      final userDataMap = {
        for (var user in usersBasicInfo) user['userId'] as String: user
      };

      // 4. Combinar applications com user data
      final results = <Map<String, dynamic>>[];
      
      for (final appDoc in applicationsSnapshot.docs) {
        final appData = appDoc.data();
        final userId = appData['userId'] as String;
        final userData = userDataMap[userId];
        
        if (userData != null) {
          results.add({
            'userId': userId,
            'photoUrl': userData['photoUrl'] as String?,
            'fullName': userData['fullName'] as String?,
            'appliedAt': appData['appliedAt'] as Timestamp?,
          });
        }
      }

      return results;
    } catch (e) {
      debugPrint('❌ Erro ao buscar aplicações recentes com user data: $e');
      return [];
    }
  }

  /// Conta total de aplicações aprovadas de um evento
  /// 
  /// Mais eficiente que buscar todas e contar
  Future<int> getApprovedApplicationsCount(String eventId) async {
    try {
      final querySnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', whereIn: [
            ApplicationStatus.approved.value,
            ApplicationStatus.autoApproved.value,
          ])
          .count()
          .get();

      return querySnapshot.count ?? 0;
    } catch (e) {
      debugPrint('❌ Erro ao contar aplicações aprovadas: $e');
      return 0;
    }
  }

  /// Conta total de todas as aplicações de um evento (qualquer status)
  Future<int> getAllApplicationsCount(String eventId) async {
    try {
      final querySnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .count()
          .get();

      return querySnapshot.count ?? 0;
    } catch (e) {
      debugPrint('❌ Erro ao contar todas as aplicações: $e');
      return 0;
    }
  }
}
