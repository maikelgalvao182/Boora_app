import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/geo_distance_helper.dart';
import 'dart:math' show cos;

class GeoService {
  // Singleton
  static final GeoService _instance = GeoService._internal();
  factory GeoService() => _instance;
  GeoService._internal();

  /// Obtém a localização atual do usuário logado (do Firestore)
  /// Busca da subcoleção privada (localização real) com fallback para documento principal
  Future<({double lat, double lng})?> getCurrentUserLocation() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return null;

    try {
      // 🔒 Primeiro tenta buscar da subcoleção privada (localização REAL)
      final privateDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .collection('private')
          .doc('location')
          .get();

      if (privateDoc.exists) {
        final privateData = privateDoc.data();
        if (privateData != null) {
          final lat = (privateData['latitude'] as num?)?.toDouble();
          final lng = (privateData['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            return (lat: lat, lng: lng);
          }
        }
      }

      // Fallback: buscar do documento principal (dados legados)
      final doc = await FirebaseFirestore.instance.collection('Users').doc(userId).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      // displayLatitude/displayLongitude (público, atual), fallback p/ latitude/longitude legados
      final lat = (data['displayLatitude'] as num?)?.toDouble() ?? 
                  (data['latitude'] as num?)?.toDouble();
      final lng = (data['displayLongitude'] as num?)?.toDouble() ?? 
                  (data['longitude'] as num?)?.toDouble();

      if (lat != null && lng != null) {
        return (lat: lat, lng: lng);
      }
    } catch (e) {
      print('Erro ao buscar localização do usuário: $e');
    }
    return null;
  }

  /// Calcula a distância entre o usuário atual e um alvo
  Future<double?> getDistanceToTarget({
    required double targetLat,
    required double targetLng,
  }) async {
    final currentLocation = await getCurrentUserLocation();

    if (currentLocation == null) return null;

    return GeoDistanceHelper.distanceInKm(
      currentLocation.lat,
      currentLocation.lng,
      targetLat,
      targetLng,
    );
  }

  /// Helper para criar bounding box
  ({double minLat, double maxLat, double minLng, double maxLng}) _buildBoundingBox(
      double lat, double lng, double radiusKm) {
    const earthRadiusKm = 6371;

    final latDelta = radiusKm / earthRadiusKm * (180 / 3.141592653589793);
    final lngDelta = radiusKm /
        (earthRadiusKm * (cos(lat * 3.141592653589793 / 180))) *
        (180 / 3.141592653589793);

    return (
      minLat: lat - latDelta,
      maxLat: lat + latDelta,
      minLng: lng - lngDelta,
      maxLng: lng + lngDelta,
    );
  }

  /// Método profissional para listar até 100 perfis num raio configurável
  /// 🔒 Usa displayLatitude/displayLongitude (com offset ~1-3km) para proteger localização real
  Future<List<Map<String, dynamic>>> getUsersWithin30Km({
    required double lat,
    required double lng,
    int limit = 100,
  }) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final box = _buildBoundingBox(lat, lng, PEOPLE_SEARCH_RADIUS_KM);

      // 🔒 SEGURANÇA: Busca usando displayLatitude (localização com offset)
      // A localização real está protegida na subcoleção private/location
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('displayLatitude', isGreaterThan: box.minLat)
          .where('displayLatitude', isLessThan: box.maxLat)
          .limit(300) // Pega um pouco mais para filtrar longitude e distância no cliente
          .get();

      List<Map<String, dynamic>> results = [];

      for (final doc in snapshot.docs) {
        if (currentUserId != null && doc.id == currentUserId) {
          continue;
        }
        final data = doc.data();

        // Usa displayLatitude/displayLongitude (com offset de privacidade)
        final userLat = (data['displayLatitude'] as num?)?.toDouble();
        final userLng = (data['displayLongitude'] as num?)?.toDouble();

        if (userLat == null || userLng == null) continue;
        
        // Filtra longitude no cliente
        if (userLng < box.minLng || userLng > box.maxLng) continue;

        final d = GeoDistanceHelper.distanceInKm(lat, lng, userLat, userLng);

        if (d <= PEOPLE_SEARCH_RADIUS_KM) {
          results.add({
            'id': doc.id,
            'data': data,
            'distance': d,
          });
        }
      }

      // Ordena por distância real
      results.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      // Retorna só os mais próximos
      return results.take(limit).toList();
    } catch (e) {
      print("Erro em getUsersWithin30Km: $e");
      return [];
    }
  }

  /// Conta quantos usuários estão num raio configurável (PEOPLE_SEARCH_RADIUS_KM)
  Future<int> countUsersWithin30Km(double lat, double lng) async {
    final users = await getUsersWithin30Km(lat: lat, lng: lng);
    return users.length;
  }
}
