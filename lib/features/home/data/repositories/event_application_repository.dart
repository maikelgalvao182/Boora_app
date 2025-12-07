import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/services/activity_notification_service.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository.dart';
import 'package:partiu/core/services/geo_index_service.dart';
import 'package:partiu/features/notifications/services/user_affinity_service.dart';
import 'package:partiu/features/notifications/services/notification_targeting_service.dart';
import 'package:partiu/features/notifications/services/notification_orchestrator.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// Repositório para gerenciar aplicações de usuários em eventos
class EventApplicationRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final UserRepository _userRepo;
  late final ActivityNotificationService _notificationService;

  EventApplicationRepository({
    FirebaseFirestore? firestore,
    UserRepository? userRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = FirebaseFunctions.instance,
        _userRepo = userRepository ?? UserRepository(firestore) {
    // Inicializar serviço de notificações com todas as dependências
    final notificationRepo = NotificationsRepository();
    final geoService = GeoIndexService(firestore: _firestore);
    final affinityService = UserAffinityService(firestore: _firestore);
    final targetingService = NotificationTargetingService(
      geoService: geoService,
      affinityService: affinityService,
      firestore: _firestore,
    );
    final orchestrator = NotificationOrchestrator(firestore: _firestore);
    
    _notificationService = ActivityNotificationService(
      notificationRepository: notificationRepo,
      targetingService: targetingService,
      orchestrator: orchestrator,
      geoIndexService: geoService,
      affinityService: affinityService,
      firestore: _firestore,
    );
  }

  /// Cria uma nova aplicação para um evento
  /// 
  /// O status é determinado automaticamente baseado no privacyType do evento:
  /// - "open" → autoApproved
  /// - "private" → pending
  /// 
  /// ⚠️ Se usuário já tiver aplicação, lança exceção
  Future<String> createApplication({
    required String eventId,
    required String userId,
    required String eventPrivacyType,
  }) async {
    // ✅ VERIFICAR se já existe aplicação deste usuário para este evento
    final existingQuery = await _firestore
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    
    if (existingQuery.docs.isNotEmpty) {
      debugPrint('⚠️ [EventApplicationRepo] Usuário já aplicou para este evento');
      throw Exception('Você já aplicou para este evento');
    }
    
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
      
      // Se foi auto-aprovado, verificar threshold para notificação "heating up"
      if (status == ApplicationStatus.autoApproved) {
        // Contar participantes aprovados
        final approvedCount = await _getApprovedParticipantsCount(eventId);
        debugPrint('🔥 Contagem de participantes aprovados: $approvedCount');
        
        // Disparar notificação se atingiu threshold
        final eventDoc = await _firestore.collection('events').doc(eventId).get();
        if (eventDoc.exists) {
          final activity = ActivityModel.fromFirestore(eventDoc);
          await _notificationService.notifyActivityHeatingUp(
            activity: activity,
            currentCount: approvedCount,
          );
          debugPrint('✅ Verificação heating up executada para $approvedCount participantes');
        }
      }
      
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

  /// Conta participantes aprovados de um evento
  Future<int> _getApprovedParticipantsCount(String eventId) async {
    try {
      final querySnapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', whereIn: ['approved', 'autoApproved'])
          .get();
      
      return querySnapshot.docs.length;
    } catch (e) {
      debugPrint('❌ Erro ao contar participantes: $e');
      return 0;
    }
  }

  /// Aprova uma aplicação (apenas para eventos privados, apenas pelo criador)
  Future<void> approveApplication(String applicationId) async {
    try {
      // Buscar dados da aplicação antes de atualizar
      final appDoc = await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('Aplicação não encontrada');
      }
      
      final appData = appDoc.data()!;
      final userId = appData['userId'] as String;
      final eventId = appData['eventId'] as String;
      
      // Atualizar status da aplicação
      await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .update({
        'status': ApplicationStatus.approved.value,
        'decisionAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Aplicação aprovada: $applicationId');
      
      // Buscar dados do evento para disparar notificação
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      if (eventDoc.exists) {
        final activity = ActivityModel.fromFirestore(eventDoc);
        
        // Disparar notificação de aprovação
        await _notificationService.notifyJoinApproved(
          activity: activity,
          approvedUserId: userId,
        );
        
        debugPrint('✅ Notificação de aprovação disparada para: $userId');
        
        // Contar participantes aprovados para verificar heating up
        final approvedCount = await _getApprovedParticipantsCount(eventId);
        debugPrint('🔥 Contagem de participantes aprovados após aprovação: $approvedCount');
        
        // Disparar notificação heating up se atingiu threshold
        await _notificationService.notifyActivityHeatingUp(
          activity: activity,
          currentCount: approvedCount,
        );
        debugPrint('✅ Verificação heating up executada para $approvedCount participantes');
      }
    } catch (e) {
      debugPrint('❌ Erro ao aprovar aplicação: $e');
      rethrow;
    }
  }

  /// Rejeita uma aplicação (apenas para eventos privados, apenas pelo criador)
  Future<void> rejectApplication(String applicationId) async {
    try {
      // Buscar dados da aplicação antes de atualizar
      final appDoc = await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('Aplicação não encontrada');
      }
      
      final appData = appDoc.data()!;
      final userId = appData['userId'] as String;
      final eventId = appData['eventId'] as String;
      
      // Atualizar status da aplicação
      await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .update({
        'status': ApplicationStatus.rejected.value,
        'decisionAt': FieldValue.serverTimestamp(),
      });

      debugPrint('❌ Aplicação rejeitada: $applicationId');
      
      // Buscar dados do evento para disparar notificação
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      if (eventDoc.exists) {
        final activity = ActivityModel.fromFirestore(eventDoc);
        
        // Disparar notificação de rejeição
        await _notificationService.notifyJoinRejected(
          activity: activity,
          rejectedUserId: userId,
        );
        
        debugPrint('❌ Notificação de rejeição disparada para: $userId');
      }
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

  /// Remove a aplicação do usuário no evento via Cloud Function
  /// 
  /// Usa Cloud Function para garantir atomicidade e segurança
  Future<void> removeUserApplication({
    required String eventId,
    required String userId,
  }) async {
    try {
      debugPrint('🔥 Chamando Cloud Function: removeUserApplication');
      debugPrint('   - eventId: $eventId');
      debugPrint('   - userId: $userId');
      
      final result = await _functions.httpsCallable('removeUserApplication').call({
        'eventId': eventId,
        'userId': userId,
      });
      
      debugPrint('✅ Cloud Function executada com sucesso');
      debugPrint('   - resultado: ${result.data}');
      
    } catch (e) {
      debugPrint('❌ Erro ao chamar removeUserApplication: $e');
      rethrow;
    }
  }
}
