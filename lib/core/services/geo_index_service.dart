import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ---------------------------------------------------------------------------
/// GEO INDEX SERVICE (Camada 0 — Infraestrutura Geográfica)
/// ---------------------------------------------------------------------------
/// Responsável por:
/// ✔ Bounding box
/// ✔ Queries geográficas otimizadas no Firestore
/// ✔ Cálculo preciso de distância (Haversine)
/// ✔ Paginação consistente para grandes volumes
/// ✔ Evitar travar a UI (usado principalmente em Triggers)
///
/// NUNCA retorna dados de UI. Apenas infraestrutura.
/// ---------------------------------------------------------------------------

class GeoIndexService {
  final FirebaseFirestore _firestore;

  static const double defaultRadiusKm = 30.0;
  static const double earthRadiusKm = 6371.0;
  static const int pageLimit = 150;

  GeoIndexService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ==========================================================================
  // PUBLIC API
  // ==========================================================================

  /// Busca **todos** os usuários dentro do raio especificado.
  ///
  /// ⚠️ IMPORTANTE:
  /// - Se existirem mais usuários que o `limit`, os excedentes serão ignorados.
  /// - Para resultados completos, use [findUsersInRadiusPaginated].
  Future<List<String>> findUsersInRadius({
    required double latitude,
    required double longitude,
    double radiusKm = defaultRadiusKm,
    List<String> excludeUserIds = const [],
    int limit = 500,
  }) async {
    print('\n🌍 [GeoIndex] findUsersInRadius() — INICIANDO');
    print('🌍 [GeoIndex] Excluir IDs: $excludeUserIds');

    final excludeSet = excludeUserIds.toSet();
    final bounds = _calculateBoundingBox(latitude, longitude, radiusKm);

    // 1. Query bounding box
    final usersInBox = await _queryBoundingBox(
      bounds: bounds,
      limit: limit,
      excludeUserIds: excludeSet,
    );

    if (usersInBox.isEmpty) {
      print('⚠️ [GeoIndex] Nenhum usuário no bounding box');
      return [];
    }

    // 2. Filtrar distância real
    final List<String> insideRadius = [];

    for (final user in usersInBox) {
      // 🛡️ Segurança redundante: garantir que ID excluído não entre
      if (excludeSet.contains(user.id)) {
        print('🚫 [GeoIndex] Bloqueando ID excluído na filtragem final: ${user.id}');
        continue;
      }

      final userLat = user.latitude;
      final userLng = user.longitude;

      if (userLat == null || userLng == null) continue;

      final distanceKm = _distanceKm(latitude, longitude, userLat, userLng);

      if (distanceKm <= radiusKm) {
        insideRadius.add(user.id);
      }
    }

    print('✅ [GeoIndex] Finalizado — Total no raio: ${insideRadius.length}');
    return insideRadius;
  }

  /// Paginação verdadeira para grandes volumes.
  ///
  /// Retorna LOTES de usuários dentro do raio (100% preciso).
  ///
  /// Ideal para:
  /// - triggers de notificação
  /// - atividades com muitos usuários próximos
  /// - uso em background
  Stream<List<String>> findUsersInRadiusPaginated({
    required double latitude,
    required double longitude,
    double radiusKm = defaultRadiusKm,
    List<String> excludeUserIds = const [],
  }) async* {
    print('\n📄 [GeoIndex] Paginação iniciada...');
    final excludeSet = excludeUserIds.toSet();
    final bounds = _calculateBoundingBox(latitude, longitude, radiusKm);

    QueryDocumentSnapshot? lastDoc;
    bool hasMore = true;
    int page = 0;

    while (hasMore) {
      page++;

      Query query = _firestore
          .collection('Users')
          .orderBy('location.latitude') // 🔥 paginação estável
          .where('location.latitude', isGreaterThanOrEqualTo: bounds.minLat)
          .where('location.latitude', isLessThanOrEqualTo: bounds.maxLat)
          .limit(pageLimit);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snap = await query.get();

      if (snap.docs.isEmpty) {
        hasMore = false;
        break;
      }

      lastDoc = snap.docs.last;

      final List<String> pageUsers = [];

      for (final doc in snap.docs) {
        final id = doc.id;

        if (excludeSet.contains(id)) continue;

        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        
        final loc = data['location'] as Map<String, dynamic>?;
        final lat = loc?['latitude'] as double?;
        final lng = loc?['longitude'] as double?;

        if (lat == null || lng == null) continue;

        // Longitude check
        if (lng < bounds.minLng || lng > bounds.maxLng) {
          continue;
        }

        // Real distance
        final distKm = _distanceKm(latitude, longitude, lat, lng);
        if (distKm <= radiusKm) pageUsers.add(id);
      }

      if (pageUsers.isNotEmpty) yield pageUsers;

      if (snap.docs.length < pageLimit) {
        hasMore = false;
      }
    }

    print('📄 [GeoIndex] Paginação encerrada.');
  }

  // ==========================================================================
  // PRIVATE HELPERS
  // ==========================================================================

  /// Calcula bounding box retornando record fortemente tipado.
  ({double minLat, double maxLat, double minLng, double maxLng})
      _calculateBoundingBox(double lat, double lng, double radiusKm) {
    final latRad = _degToRad(lat);
    final angularDistance = radiusKm / earthRadiusKm;

    final minLat = lat - _radToDeg(angularDistance);
    final maxLat = lat + _radToDeg(angularDistance);

    final deltaLng = asin(sin(angularDistance) / cos(latRad));

    final minLng = lng - _radToDeg(deltaLng);
    final maxLng = lng + _radToDeg(deltaLng);

    return (
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  /// Query Firestore + filtro básico de longitude.
  Future<List<_UserLocation>> _queryBoundingBox({
    required ({double minLat, double maxLat, double minLng, double maxLng}) bounds,
    required Set<String> excludeUserIds,
    required int limit,
  }) async {
    try {
      // 🔒 SEGURANÇA: Usa displayLatitude/displayLongitude (com offset ~1-3km)
      // A localização real está protegida na subcoleção Users/{userId}/private/location
      Query query = _firestore
          .collection('Users')
          .where('displayLatitude', isGreaterThanOrEqualTo: bounds.minLat)
          .where('displayLatitude', isLessThanOrEqualTo: bounds.maxLat)
          .orderBy('displayLatitude') // 🔥 obrigatório para paginação estável
          .limit(limit);

      final snap = await query.get();
      final List<_UserLocation> result = [];

      for (final doc in snap.docs) {
        final id = doc.id;
        if (excludeUserIds.contains(id)) continue;

        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        
        // 🔒 Usa displayLatitude/displayLongitude (localização com offset de privacidade)
        final lat = (data['displayLatitude'] as num?)?.toDouble();
        final lng = (data['displayLongitude'] as num?)?.toDouble();

        if (lat == null || lng == null) continue;

        if (lng < bounds.minLng || lng > bounds.maxLng) continue;

        result.add(_UserLocation(id: id, latitude: lat, longitude: lng));
      }

      return result;
    } catch (e) {
      print('❌ [GeoIndex] Erro bounding box: $e');
      return [];
    }
  }

  // ==========================================================================
  // MATH
  // ==========================================================================

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * pi / 180.0;

  double _radToDeg(double rad) => rad * 180.0 / pi;
}

/// Estrutura interna para localização de usuário.
/// Mantém o serviço puro e tipado sem expor modelos externos.
class _UserLocation {
  final String id;
  final double? latitude;
  final double? longitude;

  _UserLocation({
    required this.id,
    required this.latitude,
    required this.longitude,
  });
}
