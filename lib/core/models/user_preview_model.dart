import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'user_preview_model.g.dart';

/// Modelo de cache local para users_preview
/// 
/// O envelope [CachedUserPreview] mantém o dado puro [UserPreviewModel]
/// junto com metadados cruciais para a estratégia SWR (Stale-While-Revalidate).
@HiveType(typeId: 24)
class CachedUserPreview {
  @HiveField(0)
  final UserPreviewModel data;

  @HiveField(1)
  final DateTime cachedAt;

  @HiveField(2)
  final DateTime? remoteUpdatedAt;

  const CachedUserPreview({
    required this.data,
    required this.cachedAt,
    this.remoteUpdatedAt,
  });
}

/// Modelo leve de usuário para preview (listas, feeds, notificações)
@HiveType(typeId: 23)
class UserPreviewModel {
  @HiveField(0)
  final String uid;

  @HiveField(1)
  final String? fullName;

  @HiveField(2)
  final String? avatarUrl;

  @HiveField(3)
  final bool isVerified;

  @HiveField(4)
  final bool isVip;

  @HiveField(5)
  final String? city;

  @HiveField(6)
  final String? state;

  @HiveField(7)
  final String? country;

  @HiveField(8)
  final String? bio;

  @HiveField(9)
  final bool isOnline;

  @HiveField(10)
  final String status; // 'active' or 'inactive'

  const UserPreviewModel({
    required this.uid,
    this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    this.isVip = false,
    this.city,
    this.state,
    this.country,
    this.bio,
    this.isOnline = false,
    this.status = 'active',
  });

  /// Constrói a partir de um DocumentSnapshot do Firestore (users_preview/{uid})
  factory UserPreviewModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    
    // Tratamento de avatarUrl
    var rawAvatarUrl = data['avatarThumbUrl'] ?? data['photoUrl'];
    if (rawAvatarUrl is String &&
        (rawAvatarUrl.contains('googleusercontent.com') ||
            rawAvatarUrl.contains('lh3.google'))) {
      rawAvatarUrl = null;
    }

    final avatarUrl = rawAvatarUrl is String ? rawAvatarUrl : null;

    final fullName = data['fullName'] as String? ??
        data['displayName'] as String? ??
        data['name'] as String?;

    // Tratamento de isVerified
    dynamic rawVerified =
        data['isVerified'] ?? data['user_is_verified'] ?? data['verified'];
    bool isVerified = false;
    if (rawVerified is bool) {
      isVerified = rawVerified;
    } else if (rawVerified is String) {
      isVerified = rawVerified.toLowerCase() == 'true';
    }

    // Tratamento de isVip
    dynamic rawVip =
        data['isVip'] ?? data['user_is_vip'] ?? data['vip'];
    bool isVip = false;
    if (rawVip is bool) {
      isVip = rawVip;
    } else if (rawVip is String) {
      isVip = rawVip.toLowerCase() == 'true';
    }

    // Tratamento de isOnline
    dynamic rawOnline = data['isOnline'];
    bool isOnline = false;
    if (rawOnline is bool) {
      isOnline = rawOnline;
    }

    // Tratamento de status (default: 'active')
    final status = data['status'] as String? ?? 'active';

    return UserPreviewModel(
      uid: doc.id,
      fullName: fullName,
      avatarUrl: avatarUrl,
      isVerified: isVerified,
      isVip: isVip,
      isOnline: isOnline,
      city: data['locality'] as String? ?? data['city'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      bio: data['bio'] as String?,
      status: status,
    );
  }

  /// Verifica se houve mudança em dados relevantes para a UI
  /// Utilitário para evitar escrita redundante no disco (Hive)
  bool differsFrom(UserPreviewModel other) {
    return fullName != other.fullName ||
        avatarUrl != other.avatarUrl ||
        isVerified != other.isVerified ||
        isVip != other.isVip ||
        city != other.city ||
        state != other.state ||
        country != other.country ||
        isOnline != other.isOnline ||
        status != other.status;
  }
}
