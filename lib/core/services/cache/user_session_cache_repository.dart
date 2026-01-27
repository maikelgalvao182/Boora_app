import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/models/user_session_cache.dart';
import 'package:partiu/core/services/cache/hive_cache_service.dart';

/// Repositório de cache persistente para sessão do usuário
class UserSessionCacheRepository {
  static final UserSessionCacheRepository _instance =
      UserSessionCacheRepository._internal();

  factory UserSessionCacheRepository() => _instance;

  UserSessionCacheRepository._internal();

  static const String _cacheKey = 'current';
  static const Duration _defaultTtl = Duration(days: 7);

  final HiveCacheService<UserSessionCache> _cache =
      HiveCacheService<UserSessionCache>('user_session');

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _cache.initialize();
      _initialized = true;
    } catch (_) {
      // Cache é opcional
    }
  }

  Future<User?> getCachedUser({
    Duration maxAge = _defaultTtl,
  }) async {
    await _ensureInitialized();

    final cached = _cache.get(_cacheKey);
    if (cached == null) return null;

    final age = DateTime.now().difference(cached.cachedAt);
    if (age > maxAge) return null;

    try {
      return User.fromDocument(cached.data);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUser(
    User user, {
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureInitialized();

    final safeMap = _sanitizeForJson(_userToMap(user));

    final cached = UserSessionCache(
      data: safeMap,
      cachedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _cache.put(_cacheKey, cached, ttl: ttl);
  }

  Future<void> clear() async {
    await _ensureInitialized();
    await _cache.delete(_cacheKey);
  }

  Map<String, dynamic> _userToMap(User user) {
    return {
      'userId': user.userId,
      'fullName': user.userFullname,
      'photoUrl': user.photoUrl,
      'gender': user.userGender,
      'birthDay': user.userBirthDay,
      'birthMonth': user.userBirthMonth,
      'birthYear': user.userBirthYear,
      'jobTitle': user.userJobTitle,
      'bio': user.userBio,
      'country': user.userCountry,
      'locality': user.userLocality,
      'state': user.userState,
      'status': user.userStatus,
      'level': user.userLevel,
      'isVerified': user.userIsVerified,
      'totalLikes': user.userTotalLikes,
      'totalVisits': user.userTotalVisits,
      'isOnline': user.isUserOnline,
      if (user.userGallery != null) 'user_gallery': user.userGallery,
      if (user.userSettings != null) 'settings': user.userSettings,
      if (user.userInstagram != null) 'instagram': user.userInstagram,
      if (user.interests != null) 'interests': user.interests,
      if (user.languages != null) 'languages': user.languages,
      'latitude': user.userGeoPoint.latitude,
      'longitude': user.userGeoPoint.longitude,
      'registrationDate': user.userRegDate.toIso8601String(),
      'lastLoginDate': user.userLastLogin.toIso8601String(),
      if (user.pushPreferences != null) 'advancedSettings': {
        'push_preferences': user.pushPreferences,
      },
    };
  }

  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> map) {
    try {
      return (jsonDecode(jsonEncode(map)) as Map).cast<String, dynamic>();
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}