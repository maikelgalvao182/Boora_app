import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/services/global_cache_service.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/common/state/app_state.dart';

/// Repositório para gerenciar aplicações de usuários em eventos
/// 
/// 🔄 SINGLETON: Usa instância única para evitar recriação e permitir cache eficiente
class EventApplicationRepository {
  // Singleton instance
  static final EventApplicationRepository _instance = EventApplicationRepository._internal();
  
  factory EventApplicationRepository({
    FirebaseFirestore? firestore,
    UserRepository? userRepository,
  }) {
    return _instance;
  }
  
  EventApplicationRepository._internal()
      : _firestore = FirebaseFirestore.instance,
        _functions = FirebaseFunctions.instance,
        _userRepo = UserRepository();
    // ✅ Notificações agora são criadas via Cloud Functions
    // Removida inicialização do ActivityNotificationService

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final UserRepository _userRepo;
  final GlobalCacheService _cache = GlobalCacheService.instance;

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
      presence: PresenceStatus.going,
    );

    try {
      final docRef = await _firestore
          .collection('EventApplications')
          .add(application.toFirestore());

      debugPrint('✅ Aplicação criada: ${docRef.id} (status: ${status.value})');
      
      // 🗑️ INVALIDAR cache de participantes do evento
      _cache.remove('event_participants_$eventId');
      
      // ✅ Notificações agora são criadas via Cloud Functions:
      // - onActivityHeatingUp: monitora EventApplications e notifica usuários no raio
      // - onApplicationApproved (index.ts): já envia push de novo participante
      // Removidas chamadas diretas que causavam permission-denied
      
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
      // Buscar dados da aplicação antes de atualizar
      final appDoc = await _firestore
          .collection('EventApplications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('Aplicação não encontrada');
      }
      
      final appData = appDoc.data()!;
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
      
      // 🗑️ INVALIDAR cache de participantes do evento
      _cache.remove('event_participants_$eventId');
      
      // ✅ Notificações agora são criadas via Cloud Functions:
      // - onApplicationApproved (index.ts): envia push de novo participante + atualiza chat
      // - onJoinDecisionNotification: cria notificação in-app de aprovação
      // - onActivityHeatingUp: verifica threshold e notifica usuários no raio
      // Removidas chamadas diretas que causavam permission-denied
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
      
      // 🗑️ INVALIDAR cache de participantes do evento
      _cache.remove('event_participants_$eventId');
      
      // ✅ Notificação de rejeição agora é criada via Cloud Function:
      // - onJoinDecisionNotification: detecta mudança de "pending" para "rejected"
      // Removida chamada direta que causava permission-denied
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

      final applications = querySnapshot.docs
          .map((doc) => EventApplicationModel.fromFirestore(doc))
          .toList();
      
      // 🚫 Filtrar usuários bloqueados
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null) {
        final filtered = BlockService().filterBlocked<EventApplicationModel>(
          currentUserId,
          applications,
          (app) => app.userId,
        );
        debugPrint('🚫 [EventApplicationRepo] Filtrados ${applications.length - filtered.length} participantes bloqueados');
        return filtered;
      }
      
      return applications;
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

      final applications = querySnapshot.docs
          .map((doc) => EventApplicationModel.fromFirestore(doc))
          .toList();
      
      // 🚫 Filtrar usuários bloqueados
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null) {
        return BlockService().filterBlocked<EventApplicationModel>(
          currentUserId,
          applications,
          (app) => app.userId,
        );
      }
      
      return applications;
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
  /// 
  /// IMPORTANTE: Inclui o criador do evento como primeiro participante
  Future<List<Map<String, dynamic>>> getApprovedApplicationsWithUserData(String eventId) async {
    final cacheKey = 'event_participants_$eventId';
    
    // 🚀 CACHE HIT: Retornar imediatamente se existe
    final cached = _cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) {
      debugPrint('✅ [EventApplicationRepo] Cache HIT: $eventId');
      return cached;
    }
    
    debugPrint('⏳ [EventApplicationRepo] Cache MISS: buscando do Firestore...');
    
    try {
      // 0. Buscar o evento para obter o creatorId
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      final eventData = eventDoc.data();
      final creatorId = eventData?['createdBy'] as String?;
      
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

      // 2. Coletar todos os userIds (criador + applications)
      final userIds = <String>[];
      
      // Adicionar criador primeiro (sempre será o primeiro participante)
      if (creatorId != null && creatorId.isNotEmpty) {
        userIds.add(creatorId);
      }
      
      // Adicionar participantes das applications (excluindo criador se já adicionado)
      for (final doc in applicationsSnapshot.docs) {
        final userId = doc.data()['userId'] as String;
        if (!userIds.contains(userId)) {
          userIds.add(userId);
        }
      }
      
      if (userIds.isEmpty) {
        final emptyResult = <Map<String, dynamic>>[];
        _cache.set(cacheKey, emptyResult, ttl: const Duration(minutes: 3));
        return emptyResult;
      }

      // 3. Buscar dados dos usuários em batch (otimizado)
      final usersBasicInfo = await _userRepo.getUsersBasicInfo(userIds);
      
      // 4. Criar mapa userId → userData para lookup rápido
      final userDataMap = {
        for (var user in usersBasicInfo) user['userId'] as String: user
      };

      // 5. Montar lista de resultados (criador primeiro)
      final results = <Map<String, dynamic>>[];
      
      // Adicionar criador primeiro
      if (creatorId != null && userDataMap.containsKey(creatorId)) {
        final creatorData = userDataMap[creatorId];
        results.add({
          'userId': creatorId,
          'photoUrl': creatorData?['photoUrl'] as String?,
          'fullName': creatorData?['fullName'] as String?,
          'appliedAt': eventData?['createdAt'] as Timestamp?, // Usar createdAt do evento
          'isCreator': true,
        });
      }
      
      // Adicionar demais participantes das applications
      for (final appDoc in applicationsSnapshot.docs) {
        final appData = appDoc.data();
        final userId = appData['userId'] as String;
        
        // Pular se for o criador (já adicionado)
        if (userId == creatorId) continue;
        
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

      // 💾 SALVAR no cache (TTL: 3 minutos)
      _cache.set(cacheKey, results, ttl: const Duration(minutes: 3));
      debugPrint('💾 [EventApplicationRepo] Cache SAVED: $eventId (${results.length} membros)');

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
      
      // 🗑️ INVALIDAR cache de participantes do evento
      _cache.remove('event_participants_$eventId');
      
    } catch (e) {
      debugPrint('❌ Erro ao chamar removeUserApplication: $e');
      rethrow;
    }
  }

  /// Busca participantes aprovados de um evento
  /// 
  /// Retorna lista de mapas com userId, applicationId e appliedAt
  /// Ordenado por data de aplicação (antigo -> recente)
  Future<List<Map<String, dynamic>>> getParticipantsForEvent(String eventId) async {
    try {
      // Busca aplicações aprovadas do evento (approved + autoApproved)
      final snapshot = await _firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', whereIn: ['approved', 'autoApproved'])
          .get();

      // Criar lista com dados de aplicação incluindo timestamp para ordenação
      final participantsWithTimestamp = snapshot.docs.map((doc) {
        final data = doc.data();
        final appliedAt = (data['appliedAt'] as Timestamp?)?.toDate();
        
        return {
          'userId': data['userId'] as String,
          'applicationId': doc.id,
          'appliedAt': appliedAt,
        };
      }).toList();
      
      // Ordenar por data de aplicação (do mais antigo para o mais recente)
      participantsWithTimestamp.sort((a, b) {
        final aTime = a['appliedAt'] as DateTime? ?? DateTime.now();
        final bTime = b['appliedAt'] as DateTime? ?? DateTime.now();
        return aTime.compareTo(bTime);
      });

      // Retorna lista formatada
      return participantsWithTimestamp.map((p) => {
        'userId': p['userId'] as String,
        'applicationId': p['applicationId'] as String,
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar participantes do evento $eventId: $e');
      rethrow;
    }
  }

  /// 🗑️ Invalida o cache de participantes de um evento específico
  /// 
  /// Útil para forçar refresh após operações externas que modificam participantes
  void invalidateEventParticipantsCache(String eventId) {
    _cache.remove('event_participants_$eventId');
    debugPrint('🗑️ Cache invalidado para evento: $eventId');
  }
}
