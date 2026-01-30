import 'dart:async';
import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/models/user_preview_model.dart';
import 'package:partiu/core/services/cache/user_preview_cache_service.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
import 'package:partiu/core/debug/debug_flags.dart';
import 'package:flutter/foundation.dart';
// Uint8List também é exportado por foundation
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 🏆 Entry completa de usuário com dados reativos
class UserEntry {

  UserEntry({
    required this.avatarUrl, required this.avatarProvider, required this.lastUpdated, this.name,
    this.birthdate,
    this.age,
    this.gender,
    this.sexualOrientation,
    this.lookingFor,
    this.maritalStatus,
    this.bio,
    this.jobTitle,
    this.isVerified = false,
    this.isVip = false,
    this.isOnline = false,
    this.lastSeen,
    this.city,
    this.state,
    this.country,
    this.from,
    this.latitude,
    this.longitude,
    this.instagram,
    this.interests,
    this.languages,
  });
  // Dados básicos (campos do wizard)
  String? name;
  DateTime? birthdate;
  int? age;
  String? gender;
  String? sexualOrientation;
  String? lookingFor;
  String? maritalStatus;
  String? bio;
  String? jobTitle;
  
  // Avatar
  String avatarUrl;
  ImageProvider avatarProvider;
  
  // Status e verificação
  bool isVerified;
  bool isVip;
  bool isOnline;
  DateTime? lastSeen;
  
  // Localização (country é usado no wizard)
  String? city;
  String? state;
  String? country;
  String? from; // País de origem/nacionalidade
  double? latitude;
  double? longitude;
  
  // Redes sociais (apenas Instagram é usado no wizard)
  String? instagram;
  
  // Interesses (tags/categorias)
  List<String>? interests;
  
  // Idiomas (comma-separated string)
  String? languages;
  
  final DateTime lastUpdated;
}



/// Estado do avatar para evitar flash de fallback
enum AvatarState { loading, loaded, empty }

class AvatarEntry {
  const AvatarEntry(this.state, this.provider);
  final AvatarState state;
  final ImageProvider provider;
}

/// Modo de carregamento do usuário
enum UserLoadMode { 
  /// Mantém listener aberto (Chat 1x1, Perfil, Header)
  stream, 
  /// Busca única (Listas, Notificações, Comments)
  once 
}

/// 🏆 Store global de usuários com reatividade granular
/// 
/// Arquitetura CORRETA (estilo Instagram/TikTok/WhatsApp):
/// - 1 listener Firestore por userId (compartilhado por TODO o app)
/// - ValueNotifier individual por campo (rebuild cirúrgico)
/// - ImageProvider estável (zero flash)
/// 
/// Benefícios:
/// - Zero duplicate Firestore listeners
/// - Rebuild cirúrgico (só o campo que mudou reconstrói)
/// - Cache automático de dados
/// - Sincronização global instantânea
class UserStore {
  UserStore._();
  static final instance = UserStore._();

  // ✅ Fila global para evitar tempestade de downloads de avatar
  // (conexões simultâneas demais -> "connection closed" + risco de OOM/jank)
  final _AvatarPreloadQueue _avatarPreloadQueue = _AvatarPreloadQueue(
    maxConcurrent: 4,
    perItemTimeout: const Duration(seconds: 10),
    maxAttempts: 3,
  );

  // Cache de entries completas
  final Map<String, UserEntry> _users = {};
  
  // 🎯 ValueNotifiers individuais por campo (rebuild cirúrgico molecular)
  final Map<String, ValueNotifier<ImageProvider>> _avatarNotifiers = {};
  final Map<String, ValueNotifier<AvatarEntry>> _avatarEntryNotifiers = {};
  final Map<String, ValueNotifier<String?>> _nameNotifiers = {};
  final Map<String, ValueNotifier<int?>> _ageNotifiers = {};
  final Map<String, ValueNotifier<bool>> _verifiedNotifiers = {};
  final Map<String, ValueNotifier<bool>> _vipNotifiers = {};
  final Map<String, ValueNotifier<bool>> _onlineNotifiers = {};
  final Map<String, ValueNotifier<String?>> _bioNotifiers = {};
  final Map<String, ValueNotifier<String?>> _cityNotifiers = {};
  final Map<String, ValueNotifier<String?>> _stateNotifiers = {};
  final Map<String, ValueNotifier<String?>> _countryNotifiers = {};
  final Map<String, ValueNotifier<String?>> _fromNotifiers = {};
  final Map<String, ValueNotifier<List<String>?>> _interestsNotifiers = {};
  final Map<String, ValueNotifier<String?>> _languagesNotifiers = {};
  final Map<String, ValueNotifier<String?>> _instagramNotifiers = {};
  final Map<String, ValueNotifier<bool>> _messageButtonNotifiers = {};
  // Notifiers para campos do wizard foram removidos pois não são utilizados atualmente
  // Podem ser adicionados de volta quando necessário
  
  // Subscriptions do Firestore
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _previewSubscriptions = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _fullSubscriptions = {};
  
  // ✅ Notifier para broadcast de invalidação de avatar (usado por markers do mapa)
  final ValueNotifier<String?> _avatarInvalidationNotifier = ValueNotifier<String?>(null);
  
  /// Getter para escutar invalidações de avatar
  ValueNotifier<String?> get avatarInvalidationNotifier => _avatarInvalidationNotifier;

  // 🛡️ Concurrency Control para Fetches
  final Set<String> _pendingFetches = {};
  int _activeFetches = 0;
  final List<Function> _fetchQueue = [];
  static const int _maxConcurrentFetches = 6;


  // Placeholder (empty real) e placeholder de loading (transparente)
  static const _emptyAvatar = AssetImage('assets/images/empty_avatar.jpg');
  static const List<int> _kTransparentImage = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ];
  static final ImageProvider _loadingPlaceholder =
  MemoryImage(Uint8List.fromList(_kTransparentImage));

  // ========== APIs REATIVAS (Otimizadas com SWR) ==========

  /// ✅ Resolve usuário otimizando reads (SWR)
  /// 
  /// Define se usa memória, cache local ou se busca no servidor.
  void resolveUser(String userId, {UserLoadMode mode = UserLoadMode.once}) {
    if (userId.isEmpty) return;

    // 1. Memória é soberana
    if (_users.containsKey(userId)) {
      // Se já temos em memória e o modo é stream, garantimos que o listener está ativo
      if (mode == UserLoadMode.stream) {
        _ensurePreviewListening(userId);
      }
      return;
    }

    // 2. Tenta recuperar do Hive (disco)
    final envelope = UserPreviewCacheService.instance.getEnvelope(userId);
    
    if (envelope != null) {
      // ✅ CACHE HIT: Populate memória imediatamente (UX Instantânea)
      _upsertUserFromModel(userId, envelope.data);
      
      // Verificação SWR (Stale-While-Revalidate)
      final age = DateTime.now().difference(envelope.cachedAt);
      
      // Fresh Window (0-15 min): Usa cache sem revalidar
      if (age.inMinutes < 15) {
         return; 
      }
      // Se chegou aqui, está Stale ou Expired -> Revalidar
    }

    // 3. Revalidação (Cache Stale, Expired ou Miss)
    if (mode == UserLoadMode.stream) {
      _ensurePreviewListening(userId); // Legado/Realtime
    } else {
      _scheduleOneTimeFetch(userId); // Otimizado
    }
  }

  /// Bulk warmup para listas (Notificações, Comentários, etc)
  void warmingUpUsers(List<String> uids) {
    for (final uid in uids) {
      resolveUser(uid, mode: UserLoadMode.once);
    }
  }
  
  Future<void> _scheduleOneTimeFetch(String uid) async {
    if (_pendingFetches.contains(uid)) return;
    _pendingFetches.add(uid);
    
    _fetchQueue.add(() => _performFetch(uid));
    _processQueue();
  }

  void _processQueue() {
    if (_activeFetches >= _maxConcurrentFetches) return;
    if (_fetchQueue.isEmpty) return;

    _activeFetches++;
    final task = _fetchQueue.removeAt(0);
    
    // Executa e processa o próximo
    task().then((_) {
      _activeFetches--;
      _processQueue();
    });
  }

  Future<void> _performFetch(String uid) async {
    try {
      if (DebugFlags.logUserStore) {
        // AppLogger.debug('[UserStore] Fetching (ONCE): $uid');
      }
      
      final doc = await FirebaseFirestore.instance
          .collection('users_preview')
          .doc(uid)
          .get();
          
      if (doc.exists) {
         final newData = UserPreviewModel.fromFirestore(doc);
         // Atualiza cache Hive
         final currentEnvelope = UserPreviewCacheService.instance.getEnvelope(uid);
         
         // Só salva se mudou (ou se não tinha)
         if (currentEnvelope == null || newData.differsFrom(currentEnvelope.data)) {
             await UserPreviewCacheService.instance.put(uid, newData);
         }
         
         // Atualiza memória e UI
         _upsertUserFromModel(uid, newData);
      } else {
         _handleUserNotFound(uid);
      }
    } catch (e) {
      // Silently ignore
    } finally {
      _pendingFetches.remove(uid);
    }
  }

  void _upsertUserFromModel(String userId, UserPreviewModel model) {
    final avatarUrl = model.avatarUrl ?? '';
    ImageProvider provider;
    
    if (avatarUrl.isNotEmpty) {
       // Reutiliza provider se URL for a mesma para evitar flash
       final existing = _users[userId];
       if (existing != null && existing.avatarUrl == avatarUrl) {
         provider = existing.avatarProvider;
       } else {
         final cacheKey = stableImageCacheKey(avatarUrl);
         provider = CachedNetworkImageProvider(
            avatarUrl,
            cacheManager: AvatarImageCache.instance,
            cacheKey: cacheKey,
         );
       }
    } else {
       provider = _users[userId]?.avatarProvider ?? _loadingPlaceholder;
    }

    final entry = _users[userId] ?? UserEntry(
      avatarUrl: '',
      avatarProvider: _loadingPlaceholder,
      lastUpdated: DateTime.now(),
    );
    
    // Update fields
    entry.avatarUrl = avatarUrl;
    entry.avatarProvider = provider;
    entry.name = model.fullName;
    entry.isVerified = model.isVerified;
    entry.isVip = model.isVip;
    entry.isOnline = model.isOnline;
    entry.bio = model.bio;
    entry.city = model.city;
    entry.state = model.state;
    entry.country = model.country;
    
    if (!_users.containsKey(userId)) {
      _users[userId] = entry;
    }
    
    _updateNotifiers(userId, entry);
  }
  
  void _updateNotifiers(String userId, UserEntry entry) {
    if (entry.avatarUrl.isNotEmpty) {
      final avatarEntry = AvatarEntry(AvatarState.loaded, entry.avatarProvider);
      _avatarEntryNotifiers[userId]?.value = avatarEntry;
      _avatarNotifiers[userId]?.value = entry.avatarProvider;
    } else {
       // Se não tem avatar, verifica se loaded (já tratado no construtor de UserEntry default)
    }
    
    _nameNotifiers[userId]?.value = entry.name;
    _verifiedNotifiers[userId]?.value = entry.isVerified;
    _vipNotifiers[userId]?.value = entry.isVip;
    _onlineNotifiers[userId]?.value = entry.isOnline;
    _bioNotifiers[userId]?.value = entry.bio;
    _cityNotifiers[userId]?.value = entry.city;
    _stateNotifiers[userId]?.value = entry.state;
    _countryNotifiers[userId]?.value = entry.country;
  }
  
  void _handleUserNotFound(String userId) {
      _avatarEntryNotifiers[userId]?.value = const AvatarEntry(AvatarState.empty, _emptyAvatar);
  }

  // ========== APIs REATIVAS (ValueNotifiers) ==========

  /// ✅ Avatar (ImageProvider estável)

  ValueNotifier<ImageProvider> getAvatarNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<ImageProvider>(_emptyAvatar);
    _ensurePreviewListening(userId);
    return _avatarNotifiers.putIfAbsent(userId, () {
      final entry = _users[userId];
      // Estado inicial: loading (não mostra empty)
      return ValueNotifier<ImageProvider>(entry?.avatarProvider ?? _loadingPlaceholder);
    });
  }

  /// ✅ Avatar (com estado: loading/loaded/empty) para evitar flash de fallback
  /// 🔒 REGRA DE OURO: Uma vez loaded, NUNCA volta para loading
  ValueNotifier<AvatarEntry> getAvatarEntryNotifier(String userId) {
    if (userId.isEmpty) {
      return ValueNotifier<AvatarEntry>(const AvatarEntry(AvatarState.empty, _emptyAvatar));
    }
    
    // ✅ OTIMIZAÇÃO SWR: Tenta resolver via Cache/Memória/One-time Fetch
    // Evita abrir listeners de Stream desnecessários em listas
    resolveUser(userId, mode: UserLoadMode.once);
    
    // ✅ Se já existe notifier, retorna ele (NUNCA recria)
    final existing = _avatarEntryNotifiers[userId];
    if (existing != null) {
      return existing;
    }
    
    // Cria novo notifier apenas se não existia
    final existingUser = _users[userId];
    if (existingUser != null && existingUser.avatarUrl.isNotEmpty) {
      // Já temos avatar = já começa como loaded
      final notifier = ValueNotifier<AvatarEntry>(
        AvatarEntry(AvatarState.loaded, existingUser.avatarProvider),
      );
      _avatarEntryNotifiers[userId] = notifier;
      return notifier;
    } else if (existingUser != null && existingUser.avatarUrl.isEmpty) {
       // User existe na memória mas sem avatar (pode ser empty explícito)
       // Se o fetch retornou e não tinha avatar, é empty.
       final notifier = ValueNotifier<AvatarEntry>(
        AvatarEntry(AvatarState.empty, _emptyAvatar),
      );
      _avatarEntryNotifiers[userId] = notifier;
      return notifier;
    }
    
    // Primeiro acesso = loading (só na primeira vez)
    // O fetch/cache vai atualizar este notifier quando resolver
    final notifier = ValueNotifier<AvatarEntry>(
      AvatarEntry(AvatarState.loading, _loadingPlaceholder),
    );
    _avatarEntryNotifiers[userId] = notifier;
    return notifier;
  }

  /// ✅ Avatar sem listener do Firestore (reduz Read Ops)
  ///
  /// Use quando o caller já tem `photoUrl` (ex.: listas de participantes) e
  /// quer apenas renderizar a imagem com cache, sem abrir `Users/{userId}.snapshots()`.
  ///
  /// - Não cria subscription Firestore
  /// - Usa `preloadAvatar()` (cache + warmup) quando `photoUrl` é fornecida
  ValueNotifier<AvatarEntry> getAvatarEntryNotifierNoFirestore(
    String userId, {
    String? photoUrl,
  }) {
    if (userId.trim().isEmpty) {
      return ValueNotifier<AvatarEntry>(const AvatarEntry(AvatarState.empty, _emptyAvatar));
    }

    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      preloadAvatar(userId, photoUrl.trim());
    }

    final existing = _avatarEntryNotifiers[userId];
    if (existing != null) return existing;

    final existingUser = _users[userId];
    if (existingUser != null && existingUser.avatarUrl.isNotEmpty) {
      final notifier = ValueNotifier<AvatarEntry>(
        AvatarEntry(AvatarState.loaded, existingUser.avatarProvider),
      );
      _avatarEntryNotifiers[userId] = notifier;
      return notifier;
    }

    final notifier = ValueNotifier<AvatarEntry>(
      AvatarEntry(AvatarState.loading, _loadingPlaceholder),
    );
    _avatarEntryNotifiers[userId] = notifier;
    return notifier;
  }

  /// ✅ Nome
  ValueNotifier<String?> getNameNotifier(String userId) {
    if (userId.isEmpty) {
      return ValueNotifier<String?>(null);
    }
    
    _ensurePreviewListening(userId);
    
    return _nameNotifiers.putIfAbsent(userId, () {
      final currentName = _users[userId]?.name;
      return ValueNotifier<String?>(currentName);
    });
  }

  /// ✅ Idade
  ValueNotifier<int?> getAgeNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<int?>(null);
    _ensureFullListening(userId);
    return _ageNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<int?>(_users[userId]?.age);
    });
  }

  /// ✅ Verificado (badge azul)
  ValueNotifier<bool> getVerifiedNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<bool>(false);
    _ensurePreviewListening(userId);
    return _verifiedNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<bool>(_users[userId]?.isVerified ?? false);
    });
  }

  /// ✅ VIP (assinante)
  ValueNotifier<bool> getVipNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<bool>(false);
    _ensureFullListening(userId);
    return _vipNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<bool>(_users[userId]?.isVip ?? false);
    });
  }

  /// ✅ Online status
  ValueNotifier<bool> getOnlineNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<bool>(false);
    _ensureFullListening(userId);
    return _onlineNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<bool>(_users[userId]?.isOnline ?? false);
    });
  }

  /// ✅ Bio
  ValueNotifier<String?> getBioNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureFullListening(userId);
    return _bioNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.bio);
    });
  }

  /// ✅ Preferência: exibir botão de mensagem no perfil
  ///
  /// Campo do Firestore: `message_button` (bool)
  /// Default: true (usuários legados sem o campo)
  ValueNotifier<bool> getMessageButtonNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<bool>(true);
    _ensureFullListening(userId);
    return _messageButtonNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<bool>(true);
    });
  }

  /// ✅ City
  ValueNotifier<String?> getCityNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensurePreviewListening(userId);
    return _cityNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.city);
    });
  }

  /// ✅ Estado
  ValueNotifier<String?> getStateNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensurePreviewListening(userId);
    return _stateNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.state);
    });
  }

  /// ✅ País
  ValueNotifier<String?> getCountryNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensurePreviewListening(userId);
    return _countryNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.country);
    });
  }

  /// ✅ Origem/Nacionalidade (from)
  ValueNotifier<String?> getFromNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureFullListening(userId);
    return _fromNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.from);
    });
  }

  /// ✅ Interesses
  ValueNotifier<List<String>?> getInterestsNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<List<String>?>(null);
    _ensureFullListening(userId);
    return _interestsNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<List<String>?>(_users[userId]?.interests);
    });
  }

  /// ✅ Idiomas
  ValueNotifier<String?> getLanguagesNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureFullListening(userId);
    return _languagesNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.languages);
    });
  }

  /// ✅ Instagram
  ValueNotifier<String?> getInstagramNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureFullListening(userId);
    return _instagramNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.instagram);
    });
  }

  /// ✅ Define o estado do usuário manualmente e notifica
  void updateState(String userId, String? state) {
    if (userId.isEmpty) return;
    final entry = _users[userId];
    if (entry != null) {
      if (entry.state != state) {
        entry.state = state;
        _stateNotifiers[userId]?.value = state;
      }
    } else {
      // Cria nova entry simples
      _users[userId] = UserEntry(
        avatarUrl: '',
        avatarProvider: _loadingPlaceholder,
        lastUpdated: DateTime.now(),
        state: state,
      );
      _stateNotifiers[userId]?.value = state;
    }
  }

  /// ✅ Define a cidade do usuário manualmente e notifica
  void updateCity(String userId, String? city) {
    if (userId.isEmpty) return;
    final entry = _users[userId];
    if (entry != null) {
      if (entry.city != city) {
        entry.city = city;
        _cityNotifiers[userId]?.value = city;
      }
    } else {
      // Cria nova entry simples
      _users[userId] = UserEntry(
        avatarUrl: '',
        avatarProvider: _loadingPlaceholder,
        lastUpdated: DateTime.now(),
        city: city,
      );
      _cityNotifiers[userId]?.value = city;
    }
  }

  // ========== APIs SÍNCRONAS (sem reatividade) ==========

  /// Acesso síncrono ao avatar provider
  ImageProvider getAvatarProvider(String userId) {
    if (userId.isEmpty) return _emptyAvatar;
    _ensurePreviewListening(userId);
    // Durante loading, retorna placeholder transparente
    return _users[userId]?.avatarProvider ?? _loadingPlaceholder;
  }

  /// Acesso síncrono à URL do avatar (para CustomMarkerGenerator)
  String? getAvatarUrl(String userId) {
    if (userId.isEmpty) return null;
    _ensurePreviewListening(userId);
    final url = _users[userId]?.avatarUrl;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  /// Acesso síncrono ao nome
  String? getName(String userId) {
    return _users[userId]?.name;
  }

  /// Acesso síncrono à idade
  int? getAge(String userId) {
    return _users[userId]?.age;
  }

  /// Acesso síncrono à cidade
  String? getCity(String userId) {
    return _users[userId]?.city;
  }

  /// Acesso síncrono ao estado
  String? getState(String userId) {
    return _users[userId]?.state;
  }

  /// Acesso síncrono ao país
  String? getCountry(String userId) {
    return _users[userId]?.country;
  }

  /// Acesso síncrono ao status verificado
  bool isVerified(String userId) {
    return _users[userId]?.isVerified ?? false;
  }

  /// Acesso síncrono ao status online
  bool isOnline(String userId) {
    return _users[userId]?.isOnline ?? false;
  }

  /// Acesso síncrono à entry completa
  UserEntry? getUser(String userId) {
    return _users[userId];
  }

  /// Preload avatar URL (útil para otimização)
  void preloadAvatar(String userId, String avatarUrl) {
    if (userId.isEmpty || avatarUrl.isEmpty) return;
    
    // ✅ PROTEÇÃO: Se já temos a mesma URL, NÃO criar novo NetworkImage
    final existingEntry = _users[userId];
    if (existingEntry != null && existingEntry.avatarUrl == avatarUrl) {
      // URL igual = mantém instância atual (evita rebuild)
      // Apenas garante que o notifier está em estado loaded
      final currentNotifier = _avatarEntryNotifiers[userId];
      if (currentNotifier != null && currentNotifier.value.state != AvatarState.loaded) {
        currentNotifier.value = AvatarEntry(AvatarState.loaded, existingEntry.avatarProvider);
      }
      return;
    }
    
    final cacheKey = stableImageCacheKey(avatarUrl);
    ImageCacheStats.instance.record(
      category: ImageCacheCategory.avatar,
      url: avatarUrl,
      cacheKey: cacheKey,
    );

    final provider = CachedNetworkImageProvider(
      avatarUrl,
      cacheManager: AvatarImageCache.instance,
      cacheKey: cacheKey,
    );

    if (!_users.containsKey(userId)) {
      _users[userId] = UserEntry(
        avatarUrl: avatarUrl,
        avatarProvider: provider,
        lastUpdated: DateTime.now(),
      );
    } else {
      final entry = _users[userId]!;
      // Só atualiza se URL realmente mudou
      entry.avatarUrl = avatarUrl;
      entry.avatarProvider = provider;
    }
    
    final avatarEntry = AvatarEntry(AvatarState.loaded, provider);
    
    if (_avatarEntryNotifiers.containsKey(userId)) {
      _avatarEntryNotifiers[userId]!.value = avatarEntry;
    } else {
      _avatarEntryNotifiers[userId] = ValueNotifier<AvatarEntry>(avatarEntry);
    }
    
    if (_avatarNotifiers.containsKey(userId)) {
      _avatarNotifiers[userId]!.value = provider;
    } else {
      _avatarNotifiers[userId] = ValueNotifier<ImageProvider>(provider);
    }

    // ✅ Warm-up controlado via fila (concorrência limitada + retry/backoff + timeout)
    // Evita disparar dezenas/centenas de downloads simultâneos.
    _avatarPreloadQueue.enqueue(
      key: '$userId::$avatarUrl',
      task: () async {
        await _warmUpAvatarProvider(
          userId: userId,
          provider: provider,
        );

        // Só invalida (mapa) quando o avatar realmente ficou disponível no cache.
        _avatarInvalidationNotifier.value = userId;
      },
    );
  }

  /// Cancela (best-effort) preloads pendentes/retentativas de avatar.
  /// Útil quando o usuário está interagindo com o mapa (pan/zoom).
  void cancelAvatarPreloads() {
    _avatarPreloadQueue.cancelAll();
  }

  Future<void> _warmUpAvatarProvider({
    required String userId,
    required CachedNetworkImageProvider provider,
  }) async {
    // Dispara resolução/bytes no cache sem depender de BuildContext.
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<void>();

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    stream.addListener(listener);
    await completer.future;
  }

  /// Preload nome do usuário (útil para otimização)
  void preloadName(String userId, String fullName) {
    if (userId.isEmpty || fullName.isEmpty) return;
    
    // Garantir que entry existe (com valores mínimos)
    if (!_users.containsKey(userId)) {
      _users[userId] = UserEntry(
        avatarUrl: '',
        avatarProvider: const AssetImage('assets/images/empty_avatar.jpg'),
        lastUpdated: DateTime.now(),
        name: fullName,
      );
    }
    
    final entry = _users[userId]!;
    if (entry.name != fullName) {
      entry.name = fullName;
      _nameNotifiers[userId]?.value = fullName;
    }
  }

  /// Preload status de verificado (útil para otimização)
  void preloadVerified(String userId, bool verified) {
    if (userId.isEmpty) return;
    
    // Garantir que entry existe (com valores mínimos)
    if (!_users.containsKey(userId)) {
      _users[userId] = UserEntry(
        avatarUrl: '',
        avatarProvider: const AssetImage('assets/images/empty_avatar.jpg'),
        lastUpdated: DateTime.now(),
        isVerified: verified,
      );
    }
    
    final entry = _users[userId]!;
    if (entry.isVerified != verified) {
      entry.isVerified = verified;
      _verifiedNotifiers[userId]?.value = verified;
    }
  }

  /// ✅ Atualização otimista de localização (chamado após salvar no Firestore)
  /// Atualiza os notifiers imediatamente sem esperar o snapshot do Firestore
  void updateLocation(String userId, {String? city, String? state, String? country}) {
    if (userId.isEmpty) return;
    
    // Garantir que entry existe
    if (!_users.containsKey(userId)) {
      _users[userId] = UserEntry(
        avatarUrl: '',
        avatarProvider: const AssetImage('assets/images/empty_avatar.jpg'),
        lastUpdated: DateTime.now(),
        city: city,
        state: state,
        country: country,
      );
    }
    
    final entry = _users[userId]!;
    
    if (city != null && entry.city != city) {
      entry.city = city;
      _cityNotifiers[userId]?.value = city;
    }
    
    if (state != null && entry.state != state) {
      entry.state = state;
      _stateNotifiers[userId]?.value = state;
    }
    
    if (country != null && entry.country != country) {
      entry.country = country;
      _countryNotifiers[userId]?.value = country;
    }
  }

  // ========== FIRESTORE LISTENER ==========

  /// Garante que o listener do Firestore (users_preview) está ativo
  void _ensurePreviewListening(String userId) {
    if (_previewSubscriptions.containsKey(userId)) {
      // Evita spam de logs quando já ativo
      return;
    }

    if (DebugFlags.logUserStore) {
      // AppLogger.debug('[UserStore] Starting to listen for user: $userId');
    }
    
    // Cria entry inicial se não existir
    // ✅ Se já existe (preloadAvatar chamado antes), mantém os dados existentes
    _users.putIfAbsent(userId, () => UserEntry(
      avatarUrl: '',
      // Inicializa como loading (não empty)
      avatarProvider: _loadingPlaceholder,
      lastUpdated: DateTime.now(),
    ));
    
    // ✅ CRÍTICO: Só cria notifier se não existir
    // Se preloadAvatar já foi chamado, o notifier já existe com estado loaded
    // Não devemos sobrescrever com loading
    if (!_avatarEntryNotifiers.containsKey(userId)) {
      // Verifica se já temos dados carregados (preloadAvatar pode ter sido chamado)
      final existingUser = _users[userId];
      if (existingUser != null && existingUser.avatarUrl.isNotEmpty) {
        // Já temos avatar, cria com estado loaded
        _avatarEntryNotifiers[userId] = ValueNotifier<AvatarEntry>(
          AvatarEntry(AvatarState.loaded, existingUser.avatarProvider),
        );
      } else {
        // Não temos avatar ainda, cria com estado loading
        _avatarEntryNotifiers[userId] = ValueNotifier<AvatarEntry>(
          AvatarEntry(AvatarState.loading, _loadingPlaceholder),
        );
      }
    }

    _startPreviewListener(userId);
  }

  /// Garante que o listener do Firestore (Users) está ativo para campos completos
  void _ensureFullListening(String userId) {
    _ensurePreviewListening(userId);
    if (_fullSubscriptions.containsKey(userId)) return;

    _startFullListener(userId);
  }

  /// Inicia listener do Firestore (users_preview)
  void _startPreviewListener(String userId) {
    if (_previewSubscriptions.containsKey(userId)) return;

    if (DebugFlags.logUserStore) {
      // AppLogger.debug('[UserStore] Starting Firestore listener for: $userId');
    }
    
    _previewSubscriptions[userId] = FirebaseFirestore.instance
        .collection('users_preview')
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) async {
            if (DebugFlags.logUserStore) {
              // AppLogger.debug('[UserStore] Received snapshot for: $userId, exists: ${snapshot.exists}');
            }
            
            if (!snapshot.exists) {
              // Se o usuário não existe, define como empty para parar o loading
              _avatarEntryNotifiers[userId]?.value = const AvatarEntry(AvatarState.empty, _emptyAvatar);
              return;
            }
            
            final userData = snapshot.data();
            if (userData == null) {
              return;
            }

            _updatePreviewUser(userId, userData);
          },
          onError: (_) {
            // Silently ignore errors (user might be offline)
            if (DebugFlags.logUserStore) {
              // AppLogger.debug('[UserStore] Error listening to user: $userId');
            }
          },
        );
  }

  /// Inicia listener do Firestore (Users)
  void _startFullListener(String userId) {
    if (_fullSubscriptions.containsKey(userId)) return;

    if (DebugFlags.logUserStore) {
      // AppLogger.debug('[UserStore] Starting Firestore listener for full user: $userId');
    }

    _fullSubscriptions[userId] = FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) async {
            if (DebugFlags.logUserStore) {
              // AppLogger.debug('[UserStore] Received full snapshot for: $userId, exists: ${snapshot.exists}');
            }

            if (!snapshot.exists) {
              return;
            }

            final userData = snapshot.data();
            if (userData == null) {
              return;
            }

            _updateUser(userId, userData);
          },
          onError: (_) {
            if (DebugFlags.logUserStore) {
              // AppLogger.debug('[UserStore] Error listening to full user: $userId');
            }
          },
        );
  }

  /// Atualiza entry do usuário quando dados mudam no Firestore
  void _updatePreviewUser(String userId, Map<String, dynamic> userData) {
    final oldEntry = _users[userId];

    final currentNotifier = _avatarEntryNotifiers[userId];
    final currentState = currentNotifier?.value.state;
    final hadValidAvatar = currentState == AvatarState.loaded;

    var rawAvatarUrl = userData['avatarThumbUrl'] ?? userData['photoUrl'];
    if (rawAvatarUrl is String &&
        (rawAvatarUrl.contains('googleusercontent.com') ||
            rawAvatarUrl.contains('lh3.google'))) {
      rawAvatarUrl = null;
    }

    final newAvatarUrl = rawAvatarUrl is String ? rawAvatarUrl : null;

    final name = userData['fullName'] as String? ??
        userData['displayName'] as String? ??
        userData['name'] as String?;

    dynamic rawVerified =
        userData['isVerified'] ?? userData['user_is_verified'] ?? userData['verified'];
    bool isVerified = false;
    if (rawVerified is bool) {
      isVerified = rawVerified;
    } else if (rawVerified is String) {
      isVerified = rawVerified.toLowerCase() == 'true';
    }
    final resolvedVerified =
        rawVerified == null ? (oldEntry?.isVerified ?? false) : isVerified;

    dynamic rawVip =
        userData['isVip'] ?? userData['user_is_vip'] ?? userData['vip'];
    bool isVip = false;
    if (rawVip is bool) {
      isVip = rawVip;
    } else if (rawVip is String) {
      isVip = rawVip.toLowerCase() == 'true';
    }
    final resolvedVip = rawVip == null ? (oldEntry?.isVip ?? false) : isVip;

    final city = userData['locality'] as String? ?? userData['city'] as String?;
    final state = userData['state'] as String?;
    final country = userData['country'] as String?;

    final ImageProvider newAvatarProvider;
    final String effectiveAvatarUrl;

    if (newAvatarUrl == null || newAvatarUrl.isEmpty) {
      if (hadValidAvatar && oldEntry != null && oldEntry.avatarUrl.isNotEmpty) {
        newAvatarProvider = oldEntry.avatarProvider;
        effectiveAvatarUrl = oldEntry.avatarUrl;
      } else {
        newAvatarProvider = _emptyAvatar;
        effectiveAvatarUrl = '';
      }
    } else {
      if (oldEntry != null && oldEntry.avatarUrl == newAvatarUrl) {
        newAvatarProvider = oldEntry.avatarProvider;
        effectiveAvatarUrl = newAvatarUrl;
      } else {
        newAvatarProvider = CachedNetworkImageProvider(newAvatarUrl);
        effectiveAvatarUrl = newAvatarUrl;
      }
    }

    final newEntry = UserEntry(
      name: name ?? oldEntry?.name,
      age: oldEntry?.age,
      gender: oldEntry?.gender,
      sexualOrientation: oldEntry?.sexualOrientation,
      lookingFor: oldEntry?.lookingFor,
      maritalStatus: oldEntry?.maritalStatus,
      bio: oldEntry?.bio,
      jobTitle: oldEntry?.jobTitle,
      avatarUrl: effectiveAvatarUrl,
      avatarProvider: newAvatarProvider,
      isVerified: resolvedVerified,
      isVip: resolvedVip,
      isOnline: oldEntry?.isOnline ?? false,
      city: city ?? oldEntry?.city,
      state: state ?? oldEntry?.state,
      country: country ?? oldEntry?.country,
      from: oldEntry?.from,
      instagram: oldEntry?.instagram,
      interests: oldEntry?.interests,
      languages: oldEntry?.languages,
      lastUpdated: DateTime.now(),
    );

    _users[userId] = newEntry;

    void notifyChanges() {
      if (oldEntry == null || oldEntry.avatarUrl != newEntry.avatarUrl) {
        final currentEntryNotifier = _avatarEntryNotifiers[userId];
        final wasLoaded = currentEntryNotifier?.value.state == AvatarState.loaded;
        final newState = (newEntry.avatarUrl.isEmpty)
            ? AvatarState.empty
            : AvatarState.loaded;

        if (!(wasLoaded && newState == AvatarState.empty)) {
          _avatarNotifiers[userId]?.value = newAvatarProvider;
          _avatarEntryNotifiers[userId]?.value =
              AvatarEntry(newState, newAvatarProvider);
        }
      }

      if (oldEntry == null || oldEntry.name != newEntry.name) {
        _nameNotifiers[userId]?.value = newEntry.name;
      }

      if (oldEntry == null || oldEntry.isVerified != newEntry.isVerified) {
        _verifiedNotifiers[userId]?.value = newEntry.isVerified;
      }

      if (oldEntry == null || oldEntry.isVip != newEntry.isVip) {
        _vipNotifiers[userId]?.value = newEntry.isVip;
      }

      if (oldEntry == null || oldEntry.city != newEntry.city) {
        _cityNotifiers[userId]?.value = newEntry.city;
      }

      if (oldEntry == null || oldEntry.state != newEntry.state) {
        _stateNotifiers[userId]?.value = newEntry.state;
      }

      if (oldEntry == null || oldEntry.country != newEntry.country) {
        _countryNotifiers[userId]?.value = newEntry.country;
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyChanges();
      });
    } else {
      notifyChanges();
    }
  }

  /// Atualiza entry do usuário quando dados mudam no Firestore
  void _updateUser(String userId, Map<String, dynamic> userData) {
    final oldEntry = _users[userId];
    
    // ✅ PROTEÇÃO: Se já temos um avatar loaded, NUNCA permitir voltar para loading
    final currentNotifier = _avatarEntryNotifiers[userId];
    final currentState = currentNotifier?.value.state;
    final hadValidAvatar = currentState == AvatarState.loaded;

    // Extrai dados usando as chaves do modelo de cadastro (camelCase)
    // ⚠️ FILTRAR URLs do Google OAuth (dados legados)
    var rawAvatarUrl = userData['photoUrl'] as String?;
    if (rawAvatarUrl != null && 
        (rawAvatarUrl.contains('googleusercontent.com') || 
         rawAvatarUrl.contains('lh3.google'))) {
      rawAvatarUrl = null;
    }
    final newAvatarUrl = rawAvatarUrl;
    final name = userData['fullName'] as String?;
    final bio = userData['bio'] as String?;
    final gender = userData['gender'] as String?;
    final sexualOrientation = userData['sexualOrientation'] as String?;
    final String? maritalStatus = userData['maritalStatus'] as String?;
    String? lookingFor;
    final rawLookingFor = userData['lookingFor'];
    if (rawLookingFor is String) {
      lookingFor = rawLookingFor;
    } else if (rawLookingFor is List) {
      final items = rawLookingFor
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        lookingFor = items.join(',');
      }
    }
    final jobTitle = userData['jobTitle'] as String?;

    // Verificação de booleano
    // Verifica tanto isVerified (antigo) quanto user_is_verified (novo/correto)
    dynamic rawVerified = userData['user_is_verified'] ?? userData['isVerified'];
    bool isVerified = false;
    if (rawVerified is bool) {
      isVerified = rawVerified;
    } else if (rawVerified is String) {
      isVerified = rawVerified.toLowerCase() == 'true';
    }

    // VIP status (user_is_vip)
    dynamic rawVip = userData['user_is_vip'];
    bool isVip = false;
    if (rawVip is bool) {
      isVip = rawVip;
    } else if (rawVip is String) {
      isVip = rawVip.toLowerCase() == 'true';
    }

    // Online status
    dynamic rawOnline = userData['isOnline'];
    bool isOnline = false;
    if (rawOnline is bool) {
      isOnline = rawOnline;
    }

    // Localização
    final city = userData['city'] as String? ?? userData['locality'] as String?;
    final state = userData['state'] as String?;
    final country = userData['country'] as String?;
    final from = userData['from'] as String?; // País de origem/nacionalidade
    
    // Redes sociais
    final instagram = userData['instagram'] as String?;

    // Interesses (lista de strings)
    final interests = (userData['interests'] as List?)?.cast<String>();

    // Idiomas (string comma-separated)
    final languages = userData['languages'] as String?;

    // Botão de mensagem no perfil (default true)
    dynamic rawMessageButton = userData['message_button'];
    bool messageButtonEnabled = true;
    if (rawMessageButton is bool) {
      messageButtonEnabled = rawMessageButton;
    } else if (rawMessageButton is String) {
      messageButtonEnabled = rawMessageButton.toLowerCase() == 'true';
    }

    // Birthdate e idade
    int? age;
    final birthDay = userData['birthDay'] as int?;
    final birthMonth = userData['birthMonth'] as int?;
    final birthYear = userData['birthYear'] as int?;
    
    if (birthDay != null && birthMonth != null && birthYear != null) {
      final now = DateTime.now();
      final birthDate = DateTime(birthYear, birthMonth, birthDay);
      age = now.year - birthDate.year;
      // Ajustar se ainda não fez aniversário este ano
      if (now.month < birthDate.month || 
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      if (age < 0) age = null;
    }
    
    // Fallback se a idade vier calculada
    if (age == null && userData['age'] is int) {
      age = userData['age'] as int;
    }

    // ⭐ Avatar: cria provider estável (SEM cache-buster)
    // ✅ PROTEÇÃO CRÍTICA: Se já tínhamos um avatar válido, NUNCA sobrescrever com vazio
    final ImageProvider newAvatarProvider;
    final String effectiveAvatarUrl;
    
    if (newAvatarUrl == null || newAvatarUrl.isEmpty) {
      // Firestore retornou vazio, mas JÁ tínhamos avatar?
      if (hadValidAvatar && oldEntry != null && oldEntry.avatarUrl.isNotEmpty) {
        // ✅ MANTÉM o avatar anterior (proteção contra flash)
        newAvatarProvider = oldEntry.avatarProvider;
        effectiveAvatarUrl = oldEntry.avatarUrl;
      } else {
        // Realmente não tem avatar
        newAvatarProvider = _emptyAvatar;
        effectiveAvatarUrl = '';
      }
    } else {
      // ✅ PROTEÇÃO: Se URL é a mesma, NÃO recriar NetworkImage
      // Isso evita troca de instância que causa flash
      if (oldEntry != null && oldEntry.avatarUrl == newAvatarUrl) {
        // Mesma URL = mantém mesma instância do provider
        newAvatarProvider = oldEntry.avatarProvider;
        effectiveAvatarUrl = newAvatarUrl;
      } else {
        // URL diferente = cria novo NetworkImage
        newAvatarProvider = CachedNetworkImageProvider(newAvatarUrl);
        effectiveAvatarUrl = newAvatarUrl;
      }
    }

    // Cria nova entry
    final newEntry = UserEntry(
      name: name,
      age: age,
      gender: gender,
      sexualOrientation: sexualOrientation,
      lookingFor: lookingFor,
      maritalStatus: maritalStatus,
      bio: bio,
      jobTitle: jobTitle,
      avatarUrl: effectiveAvatarUrl,
      avatarProvider: newAvatarProvider,
      isVerified: isVerified,
      isVip: isVip,
      isOnline: isOnline,
      city: city,
      state: state,
      country: country,
      from: from,
      instagram: instagram,
      interests: interests,
      languages: languages,
      lastUpdated: DateTime.now(),
    );

    _users[userId] = newEntry;

    // 🎯 Notifica APENAS os campos que mudaram (rebuild cirúrgico)
    // 🛡️ PROTEÇÃO: Adia notificações para evitar "setState during build"
    void notifyChanges() {
      if (oldEntry == null || oldEntry.avatarUrl != newEntry.avatarUrl) {
        // ✅ PROTEÇÃO CRÍTICA: Nunca voltar de loaded para empty/loading
        final currentEntryNotifier = _avatarEntryNotifiers[userId];
        final wasLoaded = currentEntryNotifier?.value.state == AvatarState.loaded;
        
        // Calcula novo estado
        final newState = (newEntry.avatarUrl.isEmpty)
          ? AvatarState.empty
          : AvatarState.loaded;
        
        // ✅ Se estava loaded e novo é empty, MANTÉM o avatar anterior
        if (wasLoaded && newState == AvatarState.empty) {
          // Não atualiza - mantém o avatar que já estava funcionando
          if (DebugFlags.logUserStore) {
            // AppLogger.debug('[UserStore] Skipping avatar update (protecting loaded state)');
          }
        } else {
          _avatarNotifiers[userId]?.value = newAvatarProvider;
          _avatarEntryNotifiers[userId]?.value = AvatarEntry(newState, newAvatarProvider);
          
          if (DebugFlags.logUserStore) {
            // AppLogger.debug('[UserStore] Updated avatar for $userId: ${newEntry.avatarUrl}');
          }
          
          // ❌ REMOVIDO: _evictProvider() é PERIGOSO em scroll
          // O Flutter gerencia o cache de imagens automaticamente via LRU
          // Evict manual durante scroll causa flash do avatar
        }
      }

      if (oldEntry == null || oldEntry.name != newEntry.name) {
        _nameNotifiers[userId]?.value = newEntry.name;
        if (DebugFlags.logUserStore) {
          // AppLogger.debug('[UserStore] Updated name for $userId: ${newEntry.name}');
        }
      }

      if (oldEntry == null || oldEntry.age != newEntry.age) {
        _ageNotifiers[userId]?.value = newEntry.age;
      }

      if (oldEntry == null || oldEntry.isVerified != newEntry.isVerified) {
        _verifiedNotifiers[userId]?.value = newEntry.isVerified;
      }

      if (oldEntry == null || oldEntry.isVip != newEntry.isVip) {
        _vipNotifiers[userId]?.value = newEntry.isVip;
      }

      if (oldEntry == null || oldEntry.isOnline != newEntry.isOnline) {
        _onlineNotifiers[userId]?.value = newEntry.isOnline;
      }

      if (oldEntry == null || oldEntry.bio != newEntry.bio) {
        _bioNotifiers[userId]?.value = newEntry.bio;
      }

      if (oldEntry == null || oldEntry.city != newEntry.city) {
        _cityNotifiers[userId]?.value = newEntry.city;
      }

      if (oldEntry == null || oldEntry.state != newEntry.state) {
        _stateNotifiers[userId]?.value = newEntry.state;
      }

      if (oldEntry == null || oldEntry.country != newEntry.country) {
        _countryNotifiers[userId]?.value = newEntry.country;
      }

      if (oldEntry == null || oldEntry.from != newEntry.from) {
        _fromNotifiers[userId]?.value = newEntry.from;
      }

      // Compara listas de interesses (null-safe)
      if (oldEntry == null || !_listEquals(oldEntry.interests, newEntry.interests)) {
        _interestsNotifiers[userId]?.value = newEntry.interests;
      }

      if (oldEntry == null || oldEntry.languages != newEntry.languages) {
        _languagesNotifiers[userId]?.value = newEntry.languages;
      }

      if (oldEntry == null || oldEntry.instagram != newEntry.instagram) {
        _instagramNotifiers[userId]?.value = newEntry.instagram;
      }

      final messageButtonNotifier = _messageButtonNotifiers[userId];
      if (messageButtonNotifier != null && messageButtonNotifier.value != messageButtonEnabled) {
        messageButtonNotifier.value = messageButtonEnabled;
      }
    }
    
    // 🛡️ PROTEÇÃO: Se estamos durante build phase, adia para próximo frame
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      // Durante build - adia para depois do frame
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyChanges();
      });
    } else {
      // Fora do build - executa imediatamente
      notifyChanges();
    }
  }

  /// Evict provider do cache do Flutter
  /// ⚠️ ATENÇÃO: Usar APENAS em cleanup (logout/disposeAll)
  /// ❌ NUNCA usar durante scroll ou atualização de dados
  /// O evict manual durante scroll causa flash do avatar!
  void _evictProvider(ImageProvider provider) {
    try {
      provider.evict().then((_) {
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
    } catch (_) {
      // Ignore errors during eviction
    }
  }

  /// Helper para comparar listas (null-safe)
  bool _listEquals(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ========== CLEANUP ==========

  /// Cleanup de recursos para um userId específico
  void disposeUser(String userId) {
    _previewSubscriptions[userId]?.cancel();
    _previewSubscriptions.remove(userId);
    _fullSubscriptions[userId]?.cancel();
    _fullSubscriptions.remove(userId);
    
    final entry = _users[userId];
    if (entry != null && entry.avatarUrl.isNotEmpty) {
      _evictProvider(entry.avatarProvider);
    }

    _avatarNotifiers[userId]?.dispose();
    _avatarNotifiers.remove(userId);
    _avatarEntryNotifiers[userId]?.dispose();
    _avatarEntryNotifiers.remove(userId);
    
    _nameNotifiers[userId]?.dispose();
    _nameNotifiers.remove(userId);
    
    _ageNotifiers[userId]?.dispose();
    _ageNotifiers.remove(userId);
    
    _verifiedNotifiers[userId]?.dispose();
    _verifiedNotifiers.remove(userId);
    
    _vipNotifiers[userId]?.dispose();
    _vipNotifiers.remove(userId);
    
    _onlineNotifiers[userId]?.dispose();
    _onlineNotifiers.remove(userId);
    
    _bioNotifiers[userId]?.dispose();
    _bioNotifiers.remove(userId);
    
    _cityNotifiers[userId]?.dispose();
    _cityNotifiers.remove(userId);
    
    _stateNotifiers[userId]?.dispose();
    _stateNotifiers.remove(userId);
    
    _countryNotifiers[userId]?.dispose();
    _countryNotifiers.remove(userId);
    
    _instagramNotifiers[userId]?.dispose();
    _instagramNotifiers.remove(userId);

    _messageButtonNotifiers[userId]?.dispose();
    _messageButtonNotifiers.remove(userId);
    
    _users.remove(userId);
  }

  /// Cleanup global (para hot restart)
  void disposeAll() {
    for (final subscription in _previewSubscriptions.values) {
      subscription.cancel();
    }
    _previewSubscriptions.clear();

    for (final subscription in _fullSubscriptions.values) {
      subscription.cancel();
    }
    _fullSubscriptions.clear();

    for (final entry in _users.values) {
      if (entry.avatarUrl.isNotEmpty) {
        _evictProvider(entry.avatarProvider);
      }
    }
    _users.clear();

    for (final notifier in _avatarNotifiers.values) {
      notifier.dispose();
    }
    _avatarNotifiers.clear();

    for (final notifier in _avatarEntryNotifiers.values) {
      notifier.dispose();
    }
    _avatarEntryNotifiers.clear();

    for (final notifier in _nameNotifiers.values) {
      notifier.dispose();
    }
    _nameNotifiers.clear();

    for (final notifier in _ageNotifiers.values) {
      notifier.dispose();
    }
    _ageNotifiers.clear();

    for (final notifier in _verifiedNotifiers.values) {
      notifier.dispose();
    }
    _verifiedNotifiers.clear();

    for (final notifier in _vipNotifiers.values) {
      notifier.dispose();
    }
    _vipNotifiers.clear();

    for (final notifier in _onlineNotifiers.values) {
      notifier.dispose();
    }
    _onlineNotifiers.clear();

    for (final notifier in _bioNotifiers.values) {
      notifier.dispose();
    }
    _bioNotifiers.clear();

    for (final notifier in _cityNotifiers.values) {
      notifier.dispose();
    }
    _cityNotifiers.clear();

    for (final notifier in _stateNotifiers.values) {
      notifier.dispose();
    }
    _stateNotifiers.clear();

    for (final notifier in _countryNotifiers.values) {
      notifier.dispose();
    }
    _countryNotifiers.clear();

    for (final notifier in _messageButtonNotifiers.values) {
      notifier.dispose();
    }
    _messageButtonNotifiers.clear();
  }
}

class _AvatarPreloadQueue {
  _AvatarPreloadQueue({
    required int maxConcurrent,
    required Duration perItemTimeout,
    required int maxAttempts,
  })  : _maxConcurrent = maxConcurrent.clamp(1, 6),
        _perItemTimeout = perItemTimeout,
        _maxAttempts = maxAttempts.clamp(1, 3);

  final int _maxConcurrent;
  final Duration _perItemTimeout;
  final int _maxAttempts;

  final Queue<_AvatarPreloadTask> _queue = Queue<_AvatarPreloadTask>();
  final Set<String> _enqueuedKeys = <String>{};

  int _inFlight = 0;
  int _generation = 0;

  void enqueue({required String key, required Future<void> Function() task}) {
    if (_enqueuedKeys.contains(key)) return;
    _enqueuedKeys.add(key);
    _queue.add(_AvatarPreloadTask(key: key, run: task, generation: _generation));
    _pump();
  }

  void cancelAll() {
    _generation++;
    _queue.clear();
    _enqueuedKeys.clear();
  }

  void _pump() {
    while (_inFlight < _maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeFirst();
      _inFlight++;
      _runTask(next);
    }
  }

  Future<void> _runTask(_AvatarPreloadTask task) async {
    try {
      // Se foi cancelado depois de enfileirar, nem tenta.
      if (task.generation != _generation) {
        return;
      }

      final backoff = <Duration>[
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ];

      Object? lastError;
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        if (task.generation != _generation) {
          return;
        }

        try {
          await task.run().timeout(_perItemTimeout);
          return;
        } catch (e) {
          lastError = e;
          if (attempt >= _maxAttempts) {
            break;
          }

          final delay = backoff[(attempt - 1).clamp(0, backoff.length - 1)];
          await Future.delayed(delay);
        }
      }

      if (kDebugMode && lastError != null) {
        debugPrint('⚠️ [UserStore] Preload avatar falhou (${task.key}): $lastError');
      }
    } finally {
      _enqueuedKeys.remove(task.key);
      _inFlight = (_inFlight - 1).clamp(0, 1 << 30);
      _pump();
    }
  }
}

class _AvatarPreloadTask {
  const _AvatarPreloadTask({
    required this.key,
    required this.run,
    required this.generation,
  });

  final String key;
  final Future<void> Function() run;
  final int generation;
}

// ========== COMPATIBILITY ALIAS ==========
/// ✅ Alias para compatibilidade com código existente
class AvatarStore {
  static UserStore get instance => UserStore.instance;
}