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

/// Modelo imutável para representar um usuário
@immutable
class User {

  // Constructor
  const User({
    required this.userId,
    required this.userProfilePhoto,
    required this.userFullname,
    required this.userGender,
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
    this.photoUrl,
    this.from,
  });

  /// Safe empty user to avoid LateInitializationError before auth finishes
  factory User.empty([String userId = '']) {
    return User(
      userId: userId,
      userProfilePhoto: '',
      userFullname: '',
      userGender: '',
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
      userProfilePhoto: doc['profilePhotoUrl'] ?? '',
      userFullname: doc['fullName'] ?? '',
      userGender: doc['gender'] ?? '',
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
      languages: doc['languages'],
      photoUrl: doc['photoUrl'],
      from: doc['from'],
    );
  }
  
  /// User info
  final String userId;
  final String userProfilePhoto;
  final String userFullname;
  final String userGender;
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
  final String? photoUrl;
  final String? from; // País de origem

  /// Badge de verificação
  bool get isVerified => userIsVerified;

  // ==================== GETTERS MODERNOS ====================
  
  String get fullName => userFullname;
  String get profilePhotoUrl => userProfilePhoto.isNotEmpty ? userProfilePhoto : (photoUrl ?? '');
  String? get bio => userBio.isNotEmpty ? userBio : null;
  String? get jobTitle => userJobTitle.isNotEmpty ? userJobTitle : null;
  String? get gender => userGender.isNotEmpty ? userGender : null;
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
      final value = userGallery![key];
      
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
}