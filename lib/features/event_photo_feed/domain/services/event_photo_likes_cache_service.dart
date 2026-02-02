import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';

/// Provider singleton para o serviço de cache de likes
final eventPhotoLikesCacheServiceProvider = Provider<EventPhotoLikesCacheService>((ref) {
  return EventPhotoLikesCacheService();
});

/// Serviço de cache local para likes de fotos
/// 
/// Implementa a estratégia "estado local + Hive" para evitar N+1 queries
/// ao verificar se o usuário curtiu cada foto no feed.
/// 
/// Fluxo:
/// 1. Ao carregar o feed, verifica cache local (Set em memória)
/// 2. Se cache vazio/expirado, hidrata buscando likes recentes do Firestore
/// 3. Ao curtir/descurtir: atualiza UI instantâneo, persiste em Hive e Firestore em background
/// 
/// Benefício: custo previsível e praticamente zero reads extras em navegação normal.
class EventPhotoLikesCacheService {
  EventPhotoLikesCacheService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Cache em memória dos IDs de fotos curtidas pelo usuário atual
  final Set<String> _likedPhotoIds = {};

  /// Timestamp da última hidratação (para controle de TTL)
  DateTime? _lastHydrationAt;

  /// Cache persistente em Hive
  final HiveCacheService<List> _hiveLikesCache = HiveCacheService<List>('user_photo_likes_cache');

  bool _initialized = false;

  /// TTL da hidratação: busca novos likes a cada 24h
  static const Duration _hydrationTtl = Duration(hours: 24);

  /// Limite de likes a buscar na hidratação
  static const int _hydrationLimit = 500;

  /// Inicializa o serviço e carrega cache do Hive
  Future<void> initialize() async {
    if (_initialized) return;

    await HiveInitializer.initialize();

    try {
      await _hiveLikesCache.initialize();
      await _loadFromHive();
      _initialized = true;
      debugPrint('✅ [EventPhotoLikesCacheService] Inicializado com ${_likedPhotoIds.length} likes em cache');
    } catch (e) {
      debugPrint('⚠️ [EventPhotoLikesCacheService] Erro ao inicializar: $e');
      _initialized = true; // Continua mesmo com erro
    }
  }

  /// Carrega cache do Hive para memória
  Future<void> _loadFromHive() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final key = _cacheKey(uid);
    final data = _hiveLikesCache.get(key);

    if (data != null && data.isNotEmpty) {
      _likedPhotoIds.clear();
      _likedPhotoIds.addAll(data.whereType<String>());
      debugPrint('📦 [EventPhotoLikesCacheService] Carregado do Hive: ${_likedPhotoIds.length} likes');
    }
  }

  /// Salva cache em Hive
  Future<void> _saveToHive() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final key = _cacheKey(uid);
    await _hiveLikesCache.put(
      key,
      _likedPhotoIds.toList(growable: false),
      ttl: _hydrationTtl,
    );
  }

  String _cacheKey(String uid) => 'likes:$uid';

  /// Verifica se o usuário curtiu uma foto (consulta apenas cache local)
  /// 
  /// Retorna `true` se a foto está no cache de curtidas.
  /// Este método é O(1) e não faz nenhuma chamada de rede.
  bool isLiked(String photoId) {
    return _likedPhotoIds.contains(photoId);
  }

  /// Verifica se múltiplas fotos foram curtidas (batch)
  /// 
  /// Retorna `Map<photoId, isLiked>` para uso eficiente no feed.
  Map<String, bool> areLiked(List<String> photoIds) {
    return {
      for (final id in photoIds) id: _likedPhotoIds.contains(id),
    };
  }

  /// Adiciona uma foto ao cache de curtidas (otimistic UI)
  /// 
  /// Atualiza memória e Hive imediatamente.
  /// A persistência no Firestore deve ser feita separadamente.
  Future<void> addLike(String photoId) async {
    _likedPhotoIds.add(photoId);
    await _saveToHive();
    debugPrint('❤️ [EventPhotoLikesCacheService] Like adicionado: $photoId (total: ${_likedPhotoIds.length})');
  }

  /// Remove uma foto do cache de curtidas (otimistic UI)
  Future<void> removeLike(String photoId) async {
    _likedPhotoIds.remove(photoId);
    await _saveToHive();
    debugPrint('💔 [EventPhotoLikesCacheService] Like removido: $photoId (total: ${_likedPhotoIds.length})');
  }

  /// Verifica se precisa hidratar o cache
  bool get needsHydration {
    if (_lastHydrationAt == null) return true;
    return DateTime.now().difference(_lastHydrationAt!) > _hydrationTtl;
  }

  /// Hidrata o cache buscando likes recentes do Firestore
  /// 
  /// Deve ser chamado ao abrir o feed pela primeira vez do dia.
  /// Busca os últimos N likes do usuário e popula o cache local.
  /// 
  /// Isso é feito UMA VEZ por sessão/dia, não a cada foto!
  Future<void> hydrateIfNeeded() async {
    if (!needsHydration) {
      debugPrint('✅ [EventPhotoLikesCacheService] Cache ainda válido, pulando hidratação');
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      debugPrint('⚠️ [EventPhotoLikesCacheService] Usuário não logado, pulando hidratação');
      return;
    }

    debugPrint('🔄 [EventPhotoLikesCacheService] Iniciando hidratação para user: $uid');

    try {
      // Busca likes recentes do usuário usando collectionGroup
      // Isso busca em todas as subcoleções 'likes' de EventPhotos
      final snapshot = await _firestore
          .collectionGroup('likes')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(_hydrationLimit)
          .get();

      // Extrai os photoIds dos documentos (parent do doc de like)
      final photoIds = <String>{};
      for (final doc in snapshot.docs) {
        // O path é: EventPhotos/{photoId}/likes/{likeId}
        // Precisamos extrair o photoId
        final pathSegments = doc.reference.path.split('/');
        if (pathSegments.length >= 2) {
          // EventPhotos/ABC123/likes/XYZ → photoId = ABC123
          final photoIdIndex = pathSegments.indexOf('EventPhotos') + 1;
          if (photoIdIndex > 0 && photoIdIndex < pathSegments.length) {
            photoIds.add(pathSegments[photoIdIndex]);
          }
        }
      }

      // Atualiza cache
      _likedPhotoIds.clear();
      _likedPhotoIds.addAll(photoIds);
      _lastHydrationAt = DateTime.now();

      // Persiste em Hive
      await _saveToHive();

      debugPrint('✅ [EventPhotoLikesCacheService] Hidratação completa: ${photoIds.length} likes carregados');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('⚠️ [EventPhotoLikesCacheService] Hidratação bloqueada por rules: ${e.code}');
        _lastHydrationAt = DateTime.now();
        return;
      }

      debugPrint('❌ [EventPhotoLikesCacheService] Erro na hidratação: $e');
      // Em caso de erro, marca como hidratado para não ficar tentando em loop
      _lastHydrationAt = DateTime.now().subtract(const Duration(hours: 12));
    } catch (e) {
      debugPrint('❌ [EventPhotoLikesCacheService] Erro na hidratação: $e');
      // Em caso de erro, marca como hidratado para não ficar tentando em loop
      _lastHydrationAt = DateTime.now().subtract(const Duration(hours: 12));
    }
  }

  /// Busca likes de fotos específicas (para validar cache)
  /// 
  /// Usado quando queremos ter certeza sobre o estado de algumas fotos.
  /// Faz uma query batch para N fotos de uma vez.
  Future<Set<String>> fetchLikesForPhotos(List<String> photoIds) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty || photoIds.isEmpty) {
      return {};
    }

    debugPrint('🔍 [EventPhotoLikesCacheService] Buscando likes para ${photoIds.length} fotos');

    final likedIds = <String>{};

    try {
      // Busca em paralelo (máx 10 concurrent para não sobrecarregar)
      final chunks = _chunkList(photoIds, 10);

      for (final chunk in chunks) {
        final futures = chunk.map((photoId) {
          return _firestore
              .collection('EventPhotos')
              .doc(photoId)
              .collection('likes')
              .doc(uid)
              .get();
        });

        final results = await Future.wait(futures);

        for (var i = 0; i < results.length; i++) {
          if (results[i].exists) {
            likedIds.add(chunk[i]);
          }
        }
      }

      // Atualiza cache com os resultados
      for (final photoId in photoIds) {
        if (likedIds.contains(photoId)) {
          _likedPhotoIds.add(photoId);
        } else {
          _likedPhotoIds.remove(photoId);
        }
      }
      await _saveToHive();

      debugPrint('✅ [EventPhotoLikesCacheService] Fetch completo: ${likedIds.length}/${photoIds.length} curtidos');
      return likedIds;
    } catch (e) {
      debugPrint('❌ [EventPhotoLikesCacheService] Erro no fetch: $e');
      return likedIds;
    }
  }

  /// Limpa o cache (usado no logout)
  Future<void> clear() async {
    _likedPhotoIds.clear();
    _lastHydrationAt = null;

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _hiveLikesCache.delete(_cacheKey(uid));
    }

    debugPrint('🗑️ [EventPhotoLikesCacheService] Cache limpo');
  }

  /// Utilitário para dividir lista em chunks
  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = (i + chunkSize) > list.length ? list.length : (i + chunkSize);
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}
