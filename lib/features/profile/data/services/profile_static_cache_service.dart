import 'package:partiu/core/services/cache/hive_cache_service.dart';
import 'package:partiu/core/services/cache/hive_initializer.dart';

/// Cache persistente para dados estáticos do perfil
///
/// Armazena somente campos primitivos/serializáveis para evitar erros do Hive.
/// TTL padrão: 24h
class ProfileStaticCacheService {
  ProfileStaticCacheService._();

  static final ProfileStaticCacheService instance = ProfileStaticCacheService._();

  static const Duration defaultTtl = Duration(hours: 24);

  final HiveCacheService<Map<String, dynamic>> _cache =
      HiveCacheService<Map<String, dynamic>>('profile_static_cache');

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await HiveInitializer.initialize();
    await _cache.initialize();
    _initialized = true;
  }

  Map<String, dynamic>? get(String userId) {
    if (!_initialized) return null;
    if (userId.trim().isEmpty) return null;
    return _cache.get(_key(userId));
  }

  Future<void> put(
    String userId,
    Map<String, dynamic> data, {
    Duration ttl = defaultTtl,
  }) async {
    if (userId.trim().isEmpty) return;
    if (!_initialized) return;
    await _cache.put(_key(userId), _sanitize(data), ttl: ttl);
  }

  String _key(String userId) => 'profile_static_$userId';

  Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    final safe = <String, dynamic>{};

    void putString(String key) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        safe[key] = value;
      }
    }

    void putInt(String key) {
      final value = data[key];
      if (value is int) safe[key] = value;
      if (value is num) safe[key] = value.toInt();
    }

    void putDouble(String key) {
      final value = data[key];
      if (value is num) safe[key] = value.toDouble();
    }

    void putBool(String key) {
      final value = data[key];
      if (value is bool) safe[key] = value;
      if (value is String) {
        safe[key] = value.toLowerCase() == 'true';
      }
    }

    void putStringList(String key) {
      final value = data[key];
      if (value is List) {
        final list = value
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isNotEmpty) safe[key] = list;
      }
    }

    // IDs
    putString('userId');

    // Campos estáticos principais
    putString('photoUrl');
    putString('fullName');
    putString('bio');
    putString('jobTitle');
    putString('gender');
    putString('sexualOrientation');
    putString('lookingFor');
    putString('maritalStatus');
    putString('from');
    putString('country');
    putString('locality');
    putString('state');
    putString('instagram');
    putString('flag');

    // Datas básicas (para cálculo de idade)
    putInt('birthDay');
    putInt('birthMonth');
    putInt('birthYear');

    // Listas
    putStringList('interests');

    // Idiomas (string)
    putString('languages');

    // Gallery: aceita lista ou map simples
    final galleryRaw = data['user_gallery'];
    if (galleryRaw is List) {
      final list = galleryRaw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) safe['user_gallery'] = list;
    } else if (galleryRaw is Map) {
      final cleaned = <String, dynamic>{};
      for (final entry in galleryRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value == null) continue;
        if (value is String && value.trim().isNotEmpty) {
          cleaned[key] = value.trim();
        } else if (value is Map && value['url'] != null) {
          cleaned[key] = value['url'].toString();
        }
      }
      if (cleaned.isNotEmpty) safe['user_gallery'] = cleaned;
    }

    // Campos numéricos usados na UI
    putDouble('displayLatitude');
    putDouble('displayLongitude');

    // Flags estáticas
    putBool('isVerified');

    return safe;
  }
}
