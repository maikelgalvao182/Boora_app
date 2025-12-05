import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/locations_ranking_model.dart';

/// Serviço para gerenciar ranking de locais
/// 
/// Responsabilidades:
/// - Buscar top locais por eventos hospedados
/// - Filtrar rankings por raio geográfico
/// - Cache inteligente de resultados
class LocationsRankingService {
  final FirebaseFirestore _firestore;

  // Configurações
  static const int defaultLimit = 50;
  static const int maxLimit = 100;

  LocationsRankingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Busca ranking de locais
  /// 
  /// [limit] - Número máximo de resultados (padrão: 50)
  /// [userLat] - Latitude do usuário para filtrar por raio (opcional)
  /// [userLng] - Longitude do usuário para filtrar por raio (opcional)
  /// [radiusKm] - Raio em km para filtrar (opcional, requer lat/lng)
  Future<List<LocationRankingModel>> getLocationsRanking({
    int limit = defaultLimit,
    double? userLat,
    double? userLng,
    double? radiusKm,
  }) async {
    try {
      debugPrint('🏆 RankingService: Buscando ranking de locais (limit: $limit)');
      
      final queryLimit = radiusKm != null ? maxLimit : limit;
      
      final snapshot = await _firestore
          .collection('locationRanking')
          .orderBy('totalEventsHosted', descending: true)
          .limit(queryLimit)
          .get();

      var rankings = snapshot.docs
          .map((doc) => LocationRankingModel.fromFirestore(doc.id, doc.data()))
          .toList();

      // Filtrar por raio se fornecido
      if (radiusKm != null && userLat != null && userLng != null) {
        debugPrint('📍 Filtrando por raio: $radiusKm km');
        rankings = rankings
            .where((r) => r.isWithinRadius(
                  userLat: userLat,
                  userLng: userLng,
                  radiusKm: radiusKm,
                ))
            .take(limit)
            .toList();
      }

      debugPrint('✅ ${rankings.length} locais carregados');
      return rankings;
    } catch (error) {
      debugPrint('❌ Erro ao buscar ranking de locais: $error');
      return [];
    }
  }

  /// Busca posição de um local específico no ranking
  Future<int?> getLocationPosition(String placeId) async {
    try {
      final locationRanking = await getLocationsRanking(limit: maxLimit);
      
      final index = locationRanking.indexWhere((r) => r.placeId == placeId);
      
      return index >= 0 ? index + 1 : null;
    } catch (error) {
      debugPrint('❌ Erro ao buscar posição do local: $error');
      return null;
    }
  }
}
