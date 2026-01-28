import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Robust timestamp parser to support multiple representations
/// - Firestore Timestamp
/// - ISO-8601 String (with/without timezone)
/// - int/double epoch (ms or sec)
/// - Map with seconds/nanoseconds (Firestore JSON)
/// - DateTime
DateTime _parseDateTime(dynamic value, {DateTime? fallback}) {
  try {
    if (value == null) return fallback ?? DateTime.now();

    // Firestore Timestamp
    if (value is Timestamp) {
      return value.toDate();
    }

    // Already a DateTime
    if (value is DateTime) {
      return value;
    }

    // Numeric epoch
    if (value is int) {
      // Heuristic: > 10^12 is ms; otherwise seconds
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }
    if (value is double) {
      // Treat as seconds precision if small; else ms
      if (value > 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      } else {
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
      }
    }

    // Firestore REST style map {seconds: x, nanoseconds: y} or underscored keys
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanos = (value['nanoseconds'] ?? value['_nanoseconds']) ?? 0;
      if (seconds is int) {
        final ms = seconds * 1000 + (nanos is int ? nanos ~/ 1000000 : 0);
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }

    // ISO-8601 string
    if (value is String) {
      // Try direct parse first
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;

      // Try appending Z if missing timezone
      final parsedZ = DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z');
      if (parsedZ != null) return parsedZ;
    }
  } catch (_) {
    // Fall through to fallback
  }

  return fallback ?? DateTime.now();
}

/// Filtra URLs do Google OAuth (dados legados)
/// Essas URLs não devem ser usadas como avatar do app
String _filterGoogleOAuthUrl(String url) {
  if (url.contains('googleusercontent.com') || url.contains('lh3.google')) {
    return '';
  }
  return url;
}

/// Modelo imutável para representar um usuário
@immutable
class User {

  // Constructor
  const User({
    required this.userId,
    required this.photoUrl,
    required this.userFullname,
    required this.userGender,
    this.userSexualOrientation = '',
    required this.userBirthDay,
    required this.userBirthMonth,
    required this.userBirthYear,
    required this.userJobTitle,
    required this.userBio,
    required this.userGallery,
    required this.userCountry,
    required this.userLocality,
    required this.userGeoPoint,
    required this.userSettings, 
    required this.userStatus, 
    required this.userLevel, 
    required this.userIsVerified, 
    required this.userRegDate, 
    required this.userLastLogin, 
    required this.userDeviceToken, 
    required this.userTotalLikes, 
    required this.userTotalVisits,
    required this.isUserOnline, 
    this.userState,
    this.userInstagram,
    this.interests,
    this.languages,
    this.lookingFor,
    this.maritalStatus,
    this.from,
    this.flag,
    this.distance,
    this.displayLatitude,
    this.displayLongitude,
    this.commonInterests,
    this.overallRating,
    this.visitedAt,
    this.vipExpiresAt,
    this.vipProductId,
    this.vipUpdatedAt,
    this.vipPriority = 2,
    this.pushPreferences,
  });

  /// Safe empty user to avoid LateInitializationError before auth finishes
  factory User.empty([String userId = '']) {
    return User(
      userId: userId,
      photoUrl: '',
      userFullname: '',
      userGender: '',
      userSexualOrientation: '',
      userBirthDay: 1,
      userBirthMonth: 1,
      userBirthYear: 2000,
      userJobTitle: '',
      userBio: '',
      userGallery: const <String, dynamic>{},
      userCountry: '',
      userLocality: '',
      userGeoPoint: const GeoPoint(0, 0),
      userSettings: const <String, dynamic>{},
      userStatus: 'inactive',
      userLevel: '',
      userIsVerified: false,
      userRegDate: DateTime.fromMillisecondsSinceEpoch(0),
      userLastLogin: DateTime.fromMillisecondsSinceEpoch(0),
      userDeviceToken: '',
      userTotalLikes: 0,
      userTotalVisits: 0,
      isUserOnline: false,
      distance: null,
      displayLatitude: null,
      displayLongitude: null,
      commonInterests: null,
      overallRating: null,
      visitedAt: null,
      vipExpiresAt: null,
      vipProductId: null,
      vipUpdatedAt: null,
      vipPriority: 2,
      pushPreferences: null,
    );
  }

  /// factory user object
  factory User.fromDocument(Map<String, dynamic> doc) {
    // Helper to normalize Map-or-List fields into Map<String, dynamic>
    Map<String, dynamic>? normalizeToMap(dynamic raw) {
      if (raw == null) return null;
      try {
        if (raw is Map) {
          return raw.map((k, v) => MapEntry(k.toString(), v));
        }
        if (raw is List) {
          final map = <String, dynamic>{};
          for (var i = 0; i < raw.length; i++) {
            final v = raw[i];
            if (v == null) continue;
            map['image_$i'] = v;
          }
          return map;
        }
        if (raw is String) {
          return {'image_0': raw};
        }
      } catch (_) {
        // fallthrough to null
      }
      return null;
    }

    // Parse verification flag
    final rawVerified = doc['isVerified'];
    var parsedVerified = false;
    if (rawVerified is bool) {
      parsedVerified = rawVerified;
    } else if (rawVerified is int) {
      parsedVerified = rawVerified >= 1;
    } else if (rawVerified is String) {
      final lv = rawVerified.toLowerCase().trim();
      parsedVerified = lv == 'true' || lv == '1' || lv == 'yes';
    }

    // Parse GeoPoint (suporta formato SessionManager com latitude/longitude)
    var finalGeoPoint = const GeoPoint(0, 0);
    if (doc['latitude'] != null && doc['longitude'] != null) {
      final lat = (doc['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (doc['longitude'] as num?)?.toDouble() ?? 0.0;
      finalGeoPoint = GeoPoint(lat, lng);
    }

    return User(
      userId: doc['userId'] ?? '',
      // ⚠️ FILTRAR URLs do Google OAuth (dados legados)
      photoUrl: _filterGoogleOAuthUrl(doc['photoUrl'] ?? ''),
      userFullname: doc['fullName'] ?? '',
      userGender: doc['gender'] ?? '',
      userSexualOrientation: doc['sexualOrientation'] ?? '',
      userBirthDay: doc['birthDay'] ?? 1,
      userBirthMonth: doc['birthMonth'] ?? 1,
      userBirthYear: doc['birthYear'] ?? 2000,
      userJobTitle: doc['jobTitle'] ?? '',
      userBio: doc['bio'] ?? '',
      userGallery: normalizeToMap(doc['user_gallery']),
      userCountry: doc['country'] ?? '',
      userLocality: doc['locality'] ?? '',
      userState: doc['state'],
      userGeoPoint: finalGeoPoint,
      userSettings: normalizeToMap(doc['settings']),
      userStatus: doc['status'] ?? 'active',
      userIsVerified: parsedVerified,
      userLevel: doc['level'] ?? 'user',
      userRegDate: _parseDateTime(doc['registrationDate'], fallback: DateTime.now()),
      userLastLogin: _parseDateTime(doc['lastLoginDate'], fallback: DateTime.now()),
      userDeviceToken: '',
      userTotalLikes: doc['totalLikes'] ?? 0,
      userTotalVisits: doc['totalVisits'] ?? 0,
      isUserOnline: doc['isOnline'] ?? false,
      userInstagram: doc['instagram'],
      interests: (doc['interests'] as List?)?.cast<String>(),
      languages: doc['languages'] as String?,
      lookingFor: doc['lookingFor'] as String?,
      maritalStatus: doc['maritalStatus'] as String?,
      from: doc['from'],
      flag: doc['flag'] as String?,
      distance: (doc['distance'] as num?)?.toDouble(),
      displayLatitude: (doc['displayLatitude'] as num?)?.toDouble(),
      displayLongitude: (doc['displayLongitude'] as num?)?.toDouble(),
      commonInterests: (doc['commonInterests'] as List?)?.cast<String>(),
      overallRating: (doc['overallRating'] as num?)?.toDouble(),
      visitedAt: _parseDateTime(doc['visitedAt'], fallback: null),
      vipExpiresAt: doc['vipExpiresAt'] != null ? _parseDateTime(doc['vipExpiresAt'], fallback: null) : null,
      vipProductId: doc['vipProductId'] as String?,
      vipUpdatedAt: doc['vipUpdatedAt'] != null ? _parseDateTime(doc['vipUpdatedAt'], fallback: null) : null,
      vipPriority: doc['vip_priority'] as int? ?? 2,
      pushPreferences: normalizeToMap(doc['advancedSettings']?['push_preferences']),
    );
  }
  
  /// User info
  final String userId;
  final String photoUrl;
  final String userFullname;
  final String userGender;
  final String userSexualOrientation;
  final int userBirthDay;
  final int userBirthMonth;
  final int userBirthYear;
  final String userJobTitle;
  final String userBio;
  final String userCountry;
  final String userLocality;
  final String? userState;
  final GeoPoint userGeoPoint;
  final String userStatus;
  final bool userIsVerified;
  final String userLevel;
  final DateTime userRegDate;
  final DateTime userLastLogin;
  final String userDeviceToken;
  final int userTotalLikes;
  final int userTotalVisits;
  final Map<String, dynamic>? userGallery;
  final Map<String, dynamic>? userSettings;
  final bool isUserOnline;
  final String? userInstagram;
  final List<String>? interests;
  final String? languages;
  final String? lookingFor; // O que procura (comma-separated: friendship,networking,etc)
  final String? maritalStatus; // Estado civil
  final String? from; // País de origem
  final String? flag; // Bandeira emoji do país
  final double? distance; // Distância em km do usuário atual
  final double? displayLatitude; // Latitude com offset para privacidade
  final double? displayLongitude; // Longitude com offset para privacidade
  final List<String>? commonInterests; // Interesses em comum com o usuário logado
  final double? overallRating; // Rating geral do usuário
  final DateTime? visitedAt; // Data da visita (para ordenação)
  
  // 🔒 Campos VIP (gerenciados pelo webhook RevenueCat)
  final DateTime? vipExpiresAt; // Data de expiração do VIP (null = sem VIP)
  final String? vipProductId; // ID do produto VIP (ex: 'vip_monthly', 'vip_yearly')
  final DateTime? vipUpdatedAt; // Última atualização do status VIP
  final int vipPriority; // 1 = VIP, 2 = Free (para ordenação)
  final Map<String, dynamic>? pushPreferences;

  /// Badge de verificação
  bool get isVerified => userIsVerified;
  
  /// Verifica se usuário tem VIP ativo
  /// 
  /// ✅ Validação baseada em vipExpiresAt (mantido consistente pelo webhook)
  /// O webhook do RevenueCat garante que vipExpiresAt só tem valor quando
  /// user_is_vip=true e user_level="vip"
  bool get hasActiveVip {
    if (vipExpiresAt == null) return false;
    return vipExpiresAt!.isAfter(DateTime.now());
  }

  User copyWith({
    String? userId,
    String? photoUrl,
    String? userFullname,
    String? userGender,
    String? userSexualOrientation,
    int? userBirthDay,
    int? userBirthMonth,
    int? userBirthYear,
    String? userJobTitle,
    String? userBio,
    Map<String, dynamic>? userGallery,
    String? userCountry,
    String? userLocality,
    GeoPoint? userGeoPoint,
    Map<String, dynamic>? userSettings,
    String? userStatus,
    String? userLevel,
    bool? userIsVerified,
    DateTime? userRegDate,
    DateTime? userLastLogin,
    String? userDeviceToken,
    int? userTotalLikes,
    int? userTotalVisits,
    bool? isUserOnline,
    String? userState,
    String? userInstagram,
    List<String>? interests,
    String? languages,
    String? lookingFor,
    String? maritalStatus,
    String? from,
    String? flag,
    double? distance,
    double? displayLatitude,
    double? displayLongitude,
    List<String>? commonInterests,
    double? overallRating,
    DateTime? visitedAt,
    DateTime? vipUpdatedAt,
    int? vipPriority,
    Map<String, dynamic>? pushPreferences,
  }) {
    return User(
      userId: userId ?? this.userId,
      photoUrl: photoUrl ?? this.photoUrl,
      userFullname: userFullname ?? this.userFullname,
      userGender: userGender ?? this.userGender,
      userSexualOrientation: userSexualOrientation ?? this.userSexualOrientation,
      userBirthDay: userBirthDay ?? this.userBirthDay,
      userBirthMonth: userBirthMonth ?? this.userBirthMonth,
      userBirthYear: userBirthYear ?? this.userBirthYear,
      userJobTitle: userJobTitle ?? this.userJobTitle,
      userBio: userBio ?? this.userBio,
      userGallery: userGallery ?? this.userGallery,
      userCountry: userCountry ?? this.userCountry,
      userLocality: userLocality ?? this.userLocality,
      userGeoPoint: userGeoPoint ?? this.userGeoPoint,
      userSettings: userSettings ?? this.userSettings,
      userStatus: userStatus ?? this.userStatus,
      userLevel: userLevel ?? this.userLevel,
      userIsVerified: userIsVerified ?? this.userIsVerified,
      userRegDate: userRegDate ?? this.userRegDate,
      userLastLogin: userLastLogin ?? this.userLastLogin,
      userDeviceToken: userDeviceToken ?? this.userDeviceToken,
      userTotalLikes: userTotalLikes ?? this.userTotalLikes,
      userTotalVisits: userTotalVisits ?? this.userTotalVisits,
      isUserOnline: isUserOnline ?? this.isUserOnline,
      userState: userState ?? this.userState,
      userInstagram: userInstagram ?? this.userInstagram,
      interests: interests ?? this.interests,
      languages: languages ?? this.languages,
      lookingFor: lookingFor ?? this.lookingFor,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      from: from ?? this.from,
      flag: flag ?? this.flag,
      distance: distance ?? this.distance,
      displayLatitude: displayLatitude ?? this.displayLatitude,
      displayLongitude: displayLongitude ?? this.displayLongitude,
      commonInterests: commonInterests ?? this.commonInterests,
      overallRating: overallRating ?? this.overallRating,
      visitedAt: visitedAt ?? this.visitedAt,
      vipExpiresAt: vipExpiresAt ?? this.vipExpiresAt,
      vipProductId: vipProductId ?? this.vipProductId,
      vipUpdatedAt: vipUpdatedAt ?? this.vipUpdatedAt,
      vipPriority: vipPriority ?? this.vipPriority,
      pushPreferences: pushPreferences ?? this.pushPreferences,
    );
  }

  // ==================== GETTERS MODERNOS ====================

  // ==================== GETTERS MODERNOS ====================
  
  String get fullName => userFullname;
  String? get bio => userBio.isNotEmpty ? userBio : null;
  String? get jobTitle => userJobTitle.isNotEmpty ? userJobTitle : null;
  String? get gender => userGender.isNotEmpty ? userGender : null;
  String? get sexualOrientation => userSexualOrientation.isNotEmpty ? userSexualOrientation : null;
  int? get birthDay => userBirthDay > 0 ? userBirthDay : null;
  int? get birthMonth => userBirthMonth > 0 ? userBirthMonth : null;
  int? get birthYear => userBirthYear > 0 ? userBirthYear : null;
  String? get locality => userLocality.isNotEmpty ? userLocality : null;
  String? get state => userState?.isNotEmpty == true ? userState : null;
  String? get country => userCountry.isNotEmpty ? userCountry : null;
  String? get instagram => userInstagram;

  
  /// Lista de URLs da galeria (max 9 imagens)
  List<String>? get gallery {
    if (userGallery == null) return null;
    
    final urls = <String>[];
    for (int i = 0; i < 9; i++) {
      final key = 'image_$i';
      final value = userGallery?[key];
      
      if (value == null) {
        urls.add('');
      } else if (value is String) {
        urls.add(value);
      } else if (value is Map<String, dynamic>) {
        final url = value['url'] as String?;
        urls.add(url ?? '');
      } else {
        urls.add('');
      }
    }
    return urls;
  }
  
  /// Converte User para Map (para serialização ou modificações temporárias)
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'photoUrl': photoUrl,
      'fullName': userFullname,
      'gender': userGender,
      'birthDay': userBirthDay,
      'birthMonth': userBirthMonth,
      'birthYear': userBirthYear,
      'jobTitle': userJobTitle,
      'bio': userBio,
      'user_gallery': userGallery,
      'country': userCountry,
      'locality': userLocality,
      'state': userState,
      'latitude': userGeoPoint.latitude,
      'longitude': userGeoPoint.longitude,
      'settings': userSettings,
      'status': userStatus,
      'level': userLevel,
      'isVerified': userIsVerified,
      'registrationDate': userRegDate,
      'lastLoginDate': userLastLogin,
      'totalLikes': userTotalLikes,
      'totalVisits': userTotalVisits,
      'isOnline': isUserOnline,
      'instagram': userInstagram,
      'interests': interests,
      'languages': languages,
      'lookingFor': lookingFor,
      'maritalStatus': maritalStatus,
      'from': from,
      'flag': flag,
      'distance': distance,
      'vipProductId': vipProductId,
      'vipUpdatedAt': vipUpdatedAt,
      'vip_priority': vipPriority,
      'advancedSettings': {
        'push_preferences': pushPreferences,
      },
    };
  }
}