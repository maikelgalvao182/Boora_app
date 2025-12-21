import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
    this.bio,
    this.jobTitle,
    this.isVerified = false,
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
  String? bio;
  String? jobTitle;
  
  // Avatar
  String avatarUrl;
  ImageProvider avatarProvider;
  
  // Status e verificação
  bool isVerified;
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

  // Cache de entries completas
  final Map<String, UserEntry> _users = {};
  
  // 🎯 ValueNotifiers individuais por campo (rebuild cirúrgico molecular)
  final Map<String, ValueNotifier<ImageProvider>> _avatarNotifiers = {};
  final Map<String, ValueNotifier<AvatarEntry>> _avatarEntryNotifiers = {};
  final Map<String, ValueNotifier<String?>> _nameNotifiers = {};
  final Map<String, ValueNotifier<int?>> _ageNotifiers = {};
  final Map<String, ValueNotifier<bool>> _verifiedNotifiers = {};
  final Map<String, ValueNotifier<bool>> _onlineNotifiers = {};
  final Map<String, ValueNotifier<String?>> _bioNotifiers = {};
  final Map<String, ValueNotifier<String?>> _cityNotifiers = {};
  final Map<String, ValueNotifier<String?>> _stateNotifiers = {};
  final Map<String, ValueNotifier<String?>> _countryNotifiers = {};
  final Map<String, ValueNotifier<String?>> _fromNotifiers = {};
  final Map<String, ValueNotifier<List<String>?>> _interestsNotifiers = {};
  final Map<String, ValueNotifier<String?>> _languagesNotifiers = {};
  final Map<String, ValueNotifier<String?>> _instagramNotifiers = {};
  // Notifiers para campos do wizard foram removidos pois não são utilizados atualmente
  // Podem ser adicionados de volta quando necessário
  
  // Subscriptions do Firestore
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _subscriptions = {};
  
  // ✅ Notifier para broadcast de invalidação de avatar (usado por markers do mapa)
  final ValueNotifier<String?> _avatarInvalidationNotifier = ValueNotifier<String?>(null);
  
  /// Getter para escutar invalidações de avatar
  ValueNotifier<String?> get avatarInvalidationNotifier => _avatarInvalidationNotifier;

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

  // ========== APIs REATIVAS (ValueNotifiers) ==========

  /// ✅ Avatar (ImageProvider estável)
  ValueNotifier<ImageProvider> getAvatarNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<ImageProvider>(_emptyAvatar);
    _ensureListening(userId);
    return _avatarNotifiers.putIfAbsent(userId, () {
      final entry = _users[userId];
      // Estado inicial: loading (não mostra empty)
      return ValueNotifier<ImageProvider>(entry?.avatarProvider ?? _loadingPlaceholder);
    });
  }

  /// ✅ Avatar (com estado: loading/loaded/empty) para evitar flash de fallback
  ValueNotifier<AvatarEntry> getAvatarEntryNotifier(String userId) {
    if (userId.isEmpty) {
      return ValueNotifier<AvatarEntry>(const AvatarEntry(AvatarState.empty, _emptyAvatar));
    }
    _ensureListening(userId);
    return _avatarEntryNotifiers.putIfAbsent(userId, () {
      final existingUser = _users[userId];
      if (existingUser != null) {
        final entryState = existingUser.avatarUrl.isEmpty
            ? AvatarState.empty
            : AvatarState.loaded;
        return ValueNotifier<AvatarEntry>(AvatarEntry(entryState, existingUser.avatarProvider));
      }
      return ValueNotifier<AvatarEntry>(AvatarEntry(AvatarState.loading, _loadingPlaceholder));
    });
  }

  /// ✅ Nome
  ValueNotifier<String?> getNameNotifier(String userId) {
    if (userId.isEmpty) {
      return ValueNotifier<String?>(null);
    }
    
    _ensureListening(userId);
    
    return _nameNotifiers.putIfAbsent(userId, () {
      final currentName = _users[userId]?.name;
      return ValueNotifier<String?>(currentName);
    });
  }

  /// ✅ Idade
  ValueNotifier<int?> getAgeNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<int?>(null);
    _ensureListening(userId);
    return _ageNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<int?>(_users[userId]?.age);
    });
  }

  /// ✅ Verificado (badge azul)
  ValueNotifier<bool> getVerifiedNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<bool>(false);
    _ensureListening(userId);
    return _verifiedNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<bool>(_users[userId]?.isVerified ?? false);
    });
  }

  /// ✅ Online status
  ValueNotifier<bool> getOnlineNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<bool>(false);
    _ensureListening(userId);
    return _onlineNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<bool>(_users[userId]?.isOnline ?? false);
    });
  }

  /// ✅ Bio
  ValueNotifier<String?> getBioNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _bioNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.bio);
    });
  }

  /// ✅ City
  ValueNotifier<String?> getCityNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _cityNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.city);
    });
  }

  /// ✅ Estado
  ValueNotifier<String?> getStateNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _stateNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.state);
    });
  }

  /// ✅ País
  ValueNotifier<String?> getCountryNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _countryNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.country);
    });
  }

  /// ✅ Origem/Nacionalidade (from)
  ValueNotifier<String?> getFromNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _fromNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.from);
    });
  }

  /// ✅ Interesses
  ValueNotifier<List<String>?> getInterestsNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<List<String>?>(null);
    _ensureListening(userId);
    return _interestsNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<List<String>?>(_users[userId]?.interests);
    });
  }

  /// ✅ Idiomas
  ValueNotifier<String?> getLanguagesNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _languagesNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.languages);
    });
  }

  /// ✅ Instagram
  ValueNotifier<String?> getInstagramNotifier(String userId) {
    if (userId.isEmpty) return ValueNotifier<String?>(null);
    _ensureListening(userId);
    return _instagramNotifiers.putIfAbsent(userId, () {
      return ValueNotifier<String?>(_users[userId]?.instagram);
    });
  }

  // ========== APIs SÍNCRONAS (sem reatividade) ==========

  /// Acesso síncrono ao avatar provider
  ImageProvider getAvatarProvider(String userId) {
    if (userId.isEmpty) return _emptyAvatar;
    _ensureListening(userId);
    // Durante loading, retorna placeholder transparente
    return _users[userId]?.avatarProvider ?? _loadingPlaceholder;
  }

  /// Acesso síncrono à URL do avatar (para CustomMarkerGenerator)
  String? getAvatarUrl(String userId) {
    if (userId.isEmpty) return null;
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
    
    final provider = NetworkImage(avatarUrl);

    if (!_users.containsKey(userId)) {
      _users[userId] = UserEntry(
        avatarUrl: avatarUrl,
        avatarProvider: provider,
        lastUpdated: DateTime.now(),
      );
    } else {
      final entry = _users[userId]!;
      if (entry.avatarUrl != avatarUrl) {
        entry.avatarUrl = avatarUrl;
        entry.avatarProvider = provider;
      }
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
    
    _avatarInvalidationNotifier.value = userId;
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

  // ========== FIRESTORE LISTENER ==========

  /// Garante que o listener do Firestore está ativo
  void _ensureListening(String userId) {
    if (_subscriptions.containsKey(userId)) {
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

    _startFirestoreListener(userId);
  }

  /// Inicia listener do Firestore (Users)
  void _startFirestoreListener(String userId) {
    if (_subscriptions.containsKey(userId)) return;

    if (DebugFlags.logUserStore) {
      // AppLogger.debug('[UserStore] Starting Firestore listener for: $userId');
    }
    
    _subscriptions[userId] = FirebaseFirestore.instance
        .collection('Users')
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

            _updateUser(userId, userData);
          },
          onError: (_) {
            // Silently ignore errors (user might be offline)
            if (DebugFlags.logUserStore) {
              // AppLogger.debug('[UserStore] Error listening to user: $userId');
            }
          },
        );
  }

  /// Atualiza entry do usuário quando dados mudam no Firestore
  void _updateUser(String userId, Map<String, dynamic> userData) {
    final oldEntry = _users[userId];

    // Extrai dados usando as chaves do modelo de cadastro (camelCase)
    final newAvatarUrl = userData['photoUrl'] as String?;
    final name = userData['fullName'] as String?;
    final bio = userData['bio'] as String?;
    final gender = userData['gender'] as String?;
    final sexualOrientation = userData['sexualOrientation'] as String?;
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
    final ImageProvider newAvatarProvider;
    if (newAvatarUrl == null || newAvatarUrl.isEmpty) {
      // Empty real: só aqui aplicamos o empty asset
      newAvatarProvider = _emptyAvatar;
    } else {
      newAvatarProvider = NetworkImage(newAvatarUrl);
    }

    // Cria nova entry
    final newEntry = UserEntry(
      name: name,
      age: age,
      gender: gender,
      sexualOrientation: sexualOrientation,
      bio: bio,
      jobTitle: jobTitle,
      avatarUrl: newAvatarUrl ?? '',
      avatarProvider: newAvatarProvider,
      isVerified: isVerified,
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
        _avatarNotifiers[userId]?.value = newAvatarProvider;
        // Atualiza entry notifier com estado correto
        final entryState = (newEntry.avatarUrl.isEmpty)
          ? AvatarState.empty
          : AvatarState.loaded;
        _avatarEntryNotifiers[userId]?.value = AvatarEntry(entryState, newAvatarProvider);
        
        if (DebugFlags.logUserStore) {
          // AppLogger.debug('[UserStore] Updated avatar for $userId: ${newEntry.avatarUrl}');
        }
        
        // Evict old provider
        if (oldEntry != null && oldEntry.avatarUrl.isNotEmpty) {
          _evictProvider(oldEntry.avatarProvider);
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
    _subscriptions[userId]?.cancel();
    _subscriptions.remove(userId);
    
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
    
    _users.remove(userId);
  }

  /// Cleanup global (para hot restart)
  void disposeAll() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();

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
  }
}

// ========== COMPATIBILITY ALIAS ==========
/// ✅ Alias para compatibilidade com código existente
class AvatarStore {
  static UserStore get instance => UserStore.instance;
}