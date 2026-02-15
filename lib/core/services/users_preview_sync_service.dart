import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/geohash_helper.dart';

/// Serviço client-side que sincroniza gridId, geohash e interestBuckets
/// em `users_preview/{userId}`.
///
/// Substitui a Cloud Function `onUserLocationUpdated`, eliminando ~9.500
/// invocações/dia de Cloud Function.
///
/// Uso:
/// ```dart
/// await UsersPreviewSyncService.syncLocation(lat: -23.5, lng: -46.6);
/// await UsersPreviewSyncService.syncInterests(['pizza', 'beer_pub']);
/// ```
class UsersPreviewSyncService {
  UsersPreviewSyncService._();

  /// Tamanho do bucket de grid (deve ser IGUAL ao server: 0.05)
  static const double _gridBucketSizeDeg = 0.05;

  /// Precisão do geohash (deve ser IGUAL ao server: 7)
  static const int _geohashPrecision = 7;

  /// Mapeamento interesse → bucket (espelha interestBuckets.ts do server)
  static const Map<String, String> _interestIdToBucket = {
    // food
    'japanese': 'food',
    'pizza': 'food',
    'burgers': 'food',
    'pasta': 'food',
    'beer_pub': 'food',
    'wines': 'food',
    'sweets_cafes': 'food',
    'mexican': 'food',
    'healthy_food': 'food',
    'bbq': 'food',
    'vegetarian': 'food',
    'vegan': 'food',
    'food_markets': 'food',
    // nightlife
    'live_music_bar': 'nightlife',
    'cocktails': 'nightlife',
    'karaoke': 'nightlife',
    'nightclub': 'nightlife',
    'standup_theater': 'nightlife',
    'cinema': 'nightlife',
    'board_games': 'nightlife',
    'gaming': 'nightlife',
    'themed_parties': 'nightlife',
    'samba': 'nightlife',
    'shopping': 'nightlife',
    // culture
    'museums': 'culture',
    'book_club': 'culture',
    'photography': 'culture',
    'workshops': 'culture',
    'concerts': 'culture',
    'language_exchange': 'culture',
    'film_screenings': 'culture',
    'street_art': 'culture',
    // outdoor
    'light_trails': 'outdoor',
    'parks': 'outdoor',
    'beach': 'outdoor',
    'bike': 'outdoor',
    'climbing': 'outdoor',
    'outdoor_activities': 'outdoor',
    'pets': 'outdoor',
    'sunset': 'outdoor',
    'pool': 'outdoor',
    'camping': 'outdoor',
    // sports
    'soccer': 'sports',
    'basketball': 'sports',
    'tennis': 'sports',
    'beach_tennis': 'sports',
    'skating': 'sports',
    'running': 'sports',
    'cycling': 'sports',
    'gym': 'sports',
    'light_activities': 'sports',
    // work
    'remote_work': 'work',
    'content_creators': 'work',
    'career_talks': 'work',
    'tech_innovation': 'work',
    // wellness
    'yoga': 'wellness',
    'meditation': 'wellness',
    'pilates': 'wellness',
    'spa': 'wellness',
    'cold_plunge': 'wellness',
    'healthy_lifestyle': 'wellness',
    'relaxing_walks': 'wellness',
    // values
    'lgbtqia': 'values',
    'sustainability': 'values',
    'volunteering': 'values',
    'animal_cause': 'values',
  };

  // ──────────────────────────────────────────────
  // Cálculos (espelham server exatamente)
  // ──────────────────────────────────────────────

  /// Calcula o gridId (ex: "-470_-932")
  static String buildGridId(double lat, double lng) {
    final latBucket = (lat / _gridBucketSizeDeg).floor();
    final lngBucket = (lng / _gridBucketSizeDeg).floor();
    return '${latBucket}_$lngBucket';
  }

  /// Calcula interestBuckets a partir de lista de interesses
  static List<String> buildInterestBuckets(List<dynamic>? interests) {
    if (interests == null || interests.isEmpty) return [];
    final buckets = <String>{};
    for (final interest in interests) {
      if (interest is! String) continue;
      final normalized = interest.trim().toLowerCase();
      final bucket = _interestIdToBucket[normalized];
      if (bucket != null) {
        buckets.add(bucket);
      }
    }
    return buckets.toList();
  }

  // ──────────────────────────────────────────────
  // Sync público
  // ──────────────────────────────────────────────

  /// Sincroniza gridId + geohash em users_preview quando localização muda.
  ///
  /// Chamar após cada escrita de lat/lng em Users/{userId}.
  static Future<void> syncLocation({
    required double lat,
    required double lng,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final gridId = buildGridId(lat, lng);
      final geohash = GeohashHelper.encode(lat, lng, precision: _geohashPrecision);

      await FirebaseFirestore.instance
          .collection('users_preview')
          .doc(userId)
          .set({
        'gridId': gridId,
        'geohash': geohash,
        'latitude': lat,
        'longitude': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
          '📡 [UsersPreviewSync] Location synced → gridId=$gridId, geohash=$geohash');
    } catch (e) {
      debugPrint('⚠️ [UsersPreviewSync] syncLocation falhou: $e');
    }
  }

  /// Sincroniza interestBuckets em users_preview quando interesses mudam.
  ///
  /// Chamar após cada escrita de interests em Users/{userId}.
  static Future<void> syncInterests(List<dynamic>? interests) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final buckets = buildInterestBuckets(interests);

      await FirebaseFirestore.instance
          .collection('users_preview')
          .doc(userId)
          .set({
        'interestBuckets': buckets,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
          '📡 [UsersPreviewSync] Interests synced → buckets=$buckets');
    } catch (e) {
      debugPrint('⚠️ [UsersPreviewSync] syncInterests falhou: $e');
    }
  }

  /// Sincroniza tudo (location + interests) — útil no cadastro.
  static Future<void> syncAll({
    required double lat,
    required double lng,
    List<dynamic>? interests,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final gridId = buildGridId(lat, lng);
      final geohash = GeohashHelper.encode(lat, lng, precision: _geohashPrecision);
      final buckets = buildInterestBuckets(interests);

      await FirebaseFirestore.instance
          .collection('users_preview')
          .doc(userId)
          .set({
        'gridId': gridId,
        'geohash': geohash,
        'interestBuckets': buckets,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
          '📡 [UsersPreviewSync] Full sync → gridId=$gridId, geohash=$geohash, buckets=$buckets');
    } catch (e) {
      debugPrint('⚠️ [UsersPreviewSync] syncAll falhou: $e');
    }
  }
}
