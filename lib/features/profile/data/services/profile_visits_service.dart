import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/services/user_data_service.dart';

/// Modelo de visita ao perfil
class ProfileVisit {
  final String visitorId;
  final DateTime visitedAt;
  final String? source;
  final int visitCount;

  const ProfileVisit({
    required this.visitorId,
    required this.visitedAt,
    this.source,
    this.visitCount = 1,
  });

  factory ProfileVisit.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProfileVisit(
      visitorId: data['visitorId'] as String,
      visitedAt: (data['visitedAt'] as Timestamp).toDate(),
      source: data['source'] as String?,
      visitCount: data['visitCount'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'visitorId': visitorId,
      'visitedAt': Timestamp.fromDate(visitedAt),
      'source': source,
      'visitCount': visitCount,
    };
  }
}

/// Cache de visitas com TTL
class VisitsCache {
  final List<User> visitors;
  final DateTime timestamp;
  final String userId;

  VisitsCache({
    required this.visitors,
    required this.timestamp,
    required this.userId,
  });

  bool get isExpired => DateTime.now().difference(timestamp) > ProfileVisitsService.cacheTTL;
}

/// Serviço para gerenciar visitas ao perfil (padrão LocationQueryService)
/// 
/// Arquitetura:
/// - ✅ Cache com TTL gerenciado pelo service
/// - ✅ Stream broadcast próprio (não expõe Firestore)
/// - ✅ Interface clara: getVisitsOnce() + visitsStream
/// - ✅ Auto-reload com debounce
/// - ✅ Separação de responsabilidades
/// 
/// Features:
/// - Registro de visitas com anti-spam
/// - Contador de visitas
/// - TTL automático (7 dias para dados, 5min para cache)
/// - Sem duplicatas
class ProfileVisitsService {
  ProfileVisitsService._() {
    _initializeAutoReload();
    _initializeAuthListener();
  }
  
  static final ProfileVisitsService _instance = ProfileVisitsService._();
  static ProfileVisitsService get instance => _instance;

  final _firestore = FirebaseFirestore.instance;
  final _userRepository = UserRepository();
  final _userDataService = UserDataService.instance;
  
  // Cache de visitas por userId
  final Map<String, VisitsCache> _visitsCache = {};
  
  // Cache local para anti-spam de recordVisit
  final Map<String, DateTime> _lastVisitCache = {};
  
  // Stream controller broadcast para emitir visitas
  final _visitsStreamController = StreamController<List<User>>.broadcast();
  
  // Subscription do Firestore (para auto-reload)
  StreamSubscription<QuerySnapshot>? _firestoreSubscription;

  StreamSubscription<fire_auth.User?>? _authSubscription;
  
  // UserId sendo monitorado atualmente
  String? _currentUserId;
  
  // Timer para debounce
  Timer? _reloadDebounceTimer;
  
  // Intervalo mínimo entre visitas (anti-spam)
  static const _minVisitInterval = Duration(minutes: 15);
  
  // TTL para limpeza automática no Firestore
  static const _visitTTL = Duration(days: 7);
  
  // TTL do cache local (5 minutos)
  static const cacheTTL = Duration(minutes: 5);

  /// Stream público de visitas (broadcast)
  Stream<List<User>> get visitsStream => _visitsStreamController.stream;

  /// Verifica se o usuário atual é VIP (necessário para ver visitas)
  bool _isCurrentUserVip() {
    final user = AppState.currentUser.value;
    if (user == null) return false;
    return user.hasActiveVip;
  }

  /// Inicializa auto-reload via Firestore snapshots
  void _initializeAutoReload() {
    debugPrint('🔄 [ProfileVisitsService] Auto-reload inicializado');
  }

  void _initializeAuthListener() {
    _authSubscription ??= fire_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) return;
      reset();
    });
  }

  /// Monitora visitas de um userId específico
  /// ⚠️ NOTA: Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
  void watchUser(String userId) {
    if (_currentUserId == userId) {
      debugPrint('👀 [ProfileVisitsService] Já monitorando usuário $userId');
      return;
    }

    debugPrint('👀 [ProfileVisitsService] Iniciando monitoramento de $userId');
    
    // Cancelar subscription anterior
    _firestoreSubscription?.cancel();
    _currentUserId = userId;

    if (userId.isEmpty) {
      _visitsStreamController.add([]);
      return;
    }

    // 🔒 Verificar se o usuário é VIP antes de iniciar o stream
    // Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
    if (!_isCurrentUserVip()) {
      debugPrint('🔒 [ProfileVisitsService] Usuário não é VIP, emitindo lista vazia');
      _visitsStreamController.add([]);
      return;
    }

    // Carregar dados inicialmente
    _scheduleReload(userId);

    // Escutar mudanças do Firestore
    _firestoreSubscription = _firestore
        .collection('ProfileVisits')
        .where('visitedUserId', isEqualTo: userId)
        .orderBy('visitedAt', descending: true)
        .limit(200) // Listener limitado para evitar overfetch em realtime, mas reload carrega 1000
        .snapshots()
        .listen(
          (snapshot) {
            debugPrint('🔄 [ProfileVisitsService] Firestore snapshot recebido (${snapshot.docChanges.length} mudanças)');
            _scheduleReload(userId);
          },
          onError: (error) {
            final isPermissionDenied = error is FirebaseException && error.code == 'permission-denied';
            final isLoggedOut = fire_auth.FirebaseAuth.instance.currentUser == null;
            if (isPermissionDenied && isLoggedOut) {
              reset();
              return;
            }

            debugPrint('❌ [ProfileVisitsService] Erro no stream: $error');
          },
        );
  }

  /// Agenda reload com debounce (evita múltiplas queries simultâneas)
  void _scheduleReload(String userId) {
    _reloadDebounceTimer?.cancel();
    
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadAndEmitVisits(userId);
    });
  }

  /// Carrega visitas e emite no stream
  Future<void> _loadAndEmitVisits(String userId) async {
    final visitors = await getVisitsOnce(userId);
    if (!_visitsStreamController.isClosed) {
      _visitsStreamController.add(visitors);
    }
  }

  /// 🔥 MÉTODO PRINCIPAL: Busca visitas com cache inteligente
  /// 
  /// Uso: Carregamento inicial ou refresh manual
  /// Cache: 5 minutos por userId
  /// ⚠️ NOTA: Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
  Future<List<User>> getVisitsOnce(String userId) async {
    if (userId.isEmpty) return [];

    // 🔒 Verificar se o usuário é VIP antes de fazer a query
    // Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
    if (!_isCurrentUserVip()) {
      debugPrint('🔒 [ProfileVisitsService] Usuário não é VIP, retornando lista vazia');
      return [];
    }

    // Verificar cache
    final cached = _visitsCache[userId];
    if (cached != null && !cached.isExpired) {
      debugPrint('✅ [ProfileVisitsService] Usando cache para $userId');
      return cached.visitors;
    }

    try {
      debugPrint('📥 [ProfileVisitsService] Buscando visitas de $userId...');

      // Definir data de corte (agora - TTL)
      // Usamos visitedAt para filtro pois já existe índice com orderedBy
      final cutoffDate = DateTime.now().subtract(_visitTTL);

      // 1. Buscar visitas do Firestore
      final visitsSnapshot = await _firestore
          .collection('ProfileVisits')
          .where('visitedUserId', isEqualTo: userId)
          .where('visitedAt', isGreaterThan: Timestamp.fromDate(cutoffDate))
          .orderBy('visitedAt', descending: true)
          .limit(1000) // Aumentado limite para cobrir casos de uso reais
          .get();

      if (visitsSnapshot.docs.isEmpty) {
        _updateCache(userId, []);
        return [];
      }

      final visits = visitsSnapshot.docs
          .map((doc) => ProfileVisit.fromDoc(doc))
          .toList();

      // 2. Buscar dados do usuário atual
      final myUserData = await _userRepository.getCurrentUserData();
      if (myUserData == null) {
        debugPrint('⚠️ [ProfileVisitsService] Usuário atual não encontrado');
        return [];
      }

      // 3. Carregar dados dos visitantes usando UserDataService (com cache!)
      final visitorIds = visits.map((v) => v.visitorId).toList();
      final visitors = await _userDataService.getUsersByIds(visitorIds);
      
      if (visitors.isEmpty) {
        _updateCache(userId, []);
        return [];
      }

      // 4. Enriquecer dados (interesses, distância)
      await _userDataService.enrichUsersData(visitors, myUserData: myUserData);
      
      // 5. Adicionar timestamps de visita
      for (var i = 0; i < visitors.length; i++) {
        final visit = visits.firstWhere((v) => v.visitorId == visitors[i].userId);
        visitors[i] = visitors[i].copyWith(visitedAt: visit.visitedAt);
      }

      // 6. Buscar ratings usando UserDataService (com cache!)
      final ratingsMap = await _userDataService.getRatingsByUserIds(visitorIds);
      
      // Atualizar visitors com ratings
      for (var i = 0; i < visitors.length; i++) {
        final rating = ratingsMap[visitors[i].userId];
        if (rating != null) {
          visitors[i] = visitors[i].copyWith(overallRating: rating.averageRating);
        }
      }
      
      // 7. Ordenar por data de visita
      // 7. Ordenar por data de visita
      visitors.sort((a, b) {
        final dateA = a.visitedAt ?? DateTime(0);
        final dateB = b.visitedAt ?? DateTime(0);
        return dateB.compareTo(dateA);
      });

      // 8. Atualizar cache
      _updateCache(userId, visitors);

      debugPrint('✅ [ProfileVisitsService] ${visitors.length} visitas carregadas');
      return visitors;
    } catch (e) {
      debugPrint('❌ [ProfileVisitsService] Erro ao buscar visitas: $e');
      return [];
    }
  }

  /// Atualiza cache com timestamp
  void _updateCache(String userId, List<User> visitors) {
    _visitsCache[userId] = VisitsCache(
      visitors: visitors,
      timestamp: DateTime.now(),
      userId: userId,
    );
  }

  /// Invalida cache de um usuário específico
  void invalidateCache(String userId) {
    _visitsCache.remove(userId);
    debugPrint('🗑️ [ProfileVisitsService] Cache invalidado para $userId');
  }

  /// Força reload (invalida cache e recarrega)
  Future<void> forceReload(String userId) async {
    invalidateCache(userId);
    await _loadAndEmitVisits(userId);
  }

  /// Registra uma visita ao perfil
  /// 
  /// Anti-spam: Só registra se passaram 15 minutos desde a última visita
  /// TTL: Visita expira após 7 dias automaticamente
  Future<void> recordVisit({
    required String visitedUserId,
    String? source,
  }) async {
    final visitorId = AppState.currentUserId;
    if (visitorId == null || visitorId.isEmpty) {
      debugPrint('⚠️ [ProfileVisitsService] Usuário não autenticado');
      return;
    }

    // Não registrar visita ao próprio perfil
    if (visitorId == visitedUserId) {
      debugPrint('⚠️ [ProfileVisitsService] Não registra visita ao próprio perfil');
      return;
    }

    // Anti-spam: Verificar última visita
    final cacheKey = '${visitorId}_$visitedUserId';
    final lastVisit = _lastVisitCache[cacheKey];
    if (lastVisit != null) {
      final diff = DateTime.now().difference(lastVisit);
      if (diff < _minVisitInterval) {
        debugPrint('⏭️ [ProfileVisitsService] Visita muito recente, ignorando (${diff.inMinutes}min)');
        return;
      }
    }

    try {
      final now = DateTime.now();
      final expireAt = now.add(_visitTTL);
      
      // Buscar dados do visitante para incluir na notificação
      final visitorData = await _userRepository.getUserById(visitorId);
      final visitorName = visitorData?['fullName'] as String? ?? 'Alguém';
      final visitorPhotoUrl = visitorData?['photoUrl'] as String?;
      
      // 1. Salvar na coleção ProfileVisits (para UI de visitas)
      final docId = '${visitedUserId}_$visitorId';
      final docRef = _firestore
          .collection('ProfileVisits')
          .doc(docId);

      await docRef.set({
        'visitedUserId': visitedUserId,
        'visitorId': visitorId,
        'visitedAt': FieldValue.serverTimestamp(),
        'source': source ?? 'profile',
        'expireAt': Timestamp.fromDate(expireAt),
        'visitCount': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // 2. Salvar também na coleção ProfileViews (para notificações agregadas)
      // A Cloud Function processProfileViewNotifications monitora esta coleção
      await _firestore.collection('ProfileViews').add({
        'viewerId': visitorId,
        'viewedUserId': visitedUserId,
        'viewedAt': FieldValue.serverTimestamp(),
        'notified': false, // Será marcado como true pela Cloud Function
        'viewerName': visitorName,
        'viewerPhotoUrl': visitorPhotoUrl,
      });

      // Atualizar cache local
      _lastVisitCache[cacheKey] = now;
      
      debugPrint('✅ [ProfileVisitsService] Visita registrada: $visitorId -> $visitedUserId');
    } catch (e) {
      debugPrint('❌ [ProfileVisitsService] Erro ao registrar visita: $e');
    }
  }

  /// Busca contador de visitas (one-time fetch)
  /// 
  /// Nota: O app registra visitas incrementando o campo `visitCount` por visitante.
  /// Aqui retornamos a soma desse campo (não apenas quantidade de documentos).
  Future<int> getVisitsCount(String userId) async {
    if (userId.isEmpty) return 0;

    // Se não há usuário logado, não há permissão para consultar.
    // Evita "permission-denied" tardio (pós-logout) e ruído no console.
    if (fire_auth.FirebaseAuth.instance.currentUser == null) {
      return 0;
    }

    try {
      // Soma `visitCount` dos docs do usuário.
      // Mantém consistente com a forma como as visitas são registradas.
      final snapshot = await _firestore
          .collection('ProfileVisits')
          .where('visitedUserId', isEqualTo: userId)
          .get();

      var total = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final value = data['visitCount'];
        if (value is int) {
          total += value;
        } else if (value is num) {
          total += value.toInt();
        } else {
          // Fallback: se o doc não tem visitCount (legado), conta como 1.
          total += 1;
        }
      }

      return total;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 0;
      }
      debugPrint('❌ [ProfileVisitsService] Erro ao contar visitas: $e');
      return 0;
    } on PlatformException catch (e) {
      if (e.code == 'permission-denied') {
        return 0;
      }
      debugPrint('❌ [ProfileVisitsService] Erro ao contar visitas: $e');
      return 0;
    } catch (e) {
      debugPrint('❌ [ProfileVisitsService] Erro ao contar visitas: $e');
      return 0;
    }
  }

  /// Limpa todos os caches (útil após logout)
  void clearAllCaches() {
    _lastVisitCache.clear();
    _visitsCache.clear();
    _firestoreSubscription?.cancel();
    _currentUserId = null;
    debugPrint('🗑️ [ProfileVisitsService] Todos os caches limpos');
  }

  /// Reseta estado/streams para evitar erros após logout
  void reset() {
    clearAllCaches();
    _reloadDebounceTimer?.cancel();
    if (!_visitsStreamController.isClosed) {
      _visitsStreamController.add([]);
    }
  }

  /// Dispose (limpa recursos)
  void dispose() {
    _firestoreSubscription?.cancel();
    _authSubscription?.cancel();
    _reloadDebounceTimer?.cancel();
    _visitsStreamController.close();
  }
}