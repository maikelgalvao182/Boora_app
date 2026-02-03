import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/ranking_filters_model.dart';
import 'package:partiu/features/home/data/models/user_ranking_model.dart';

/// Serviço para gerenciar ranking de pessoas baseado em reviews
/// 
/// Responsabilidades:
/// - Buscar reviews da coleção Reviews
/// - Cruzar com dados de usuários
/// - Filtrar por cidade
/// - Retornar lista ordenada por rating
class PeopleRankingService {
  final FirebaseFirestore _firestore;
  PeopleRankingMetrics? _lastMetrics;
  DocumentSnapshot<Map<String, dynamic>>? _lastReviewDoc;

  // ⚠️ NOTA: Firestore NÃO permite buscar campos específicos com whereIn
  // Esta lista documenta campos necessários, mas ainda lemos docs completos
  // Para otimização real, seria necessário criar coleção users_preview separada
  static const _requiredUserFields = [
    'fullName',
    'photoUrl',
    'locality',
    'state',
    'overallRating',
    'jobTitle',
  ];

  PeopleRankingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  PeopleRankingMetrics? get lastMetrics => _lastMetrics;
  DocumentSnapshot<Map<String, dynamic>>? get lastReviewDoc => _lastReviewDoc;

  Future<RankingFilters?> getRankingFilters() async {
    try {
      final snapshot = await _firestore
          .collection('ranking_filters')
          .doc('current')
          .get();

      if (!snapshot.exists) return null;

      final data = snapshot.data();
      if (data == null) return null;

      return RankingFilters.fromMap(data);
    } catch (e) {
      debugPrint('⚠️ [PeopleRankingService] Falha ao buscar ranking_filters: $e');
      return null;
    }
  }

  /// Busca ranking de pessoas baseado em reviews
  /// 
  /// [selectedState] - Estado para filtrar (opcional)
  /// [selectedLocality] - Cidade para filtrar (opcional)
  /// [limit] - Limite de resultados (padrão: 50)
  Future<List<UserRankingModel>> getPeopleRanking({
    String? selectedState,
    String? selectedLocality,
    int limit = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfterReviewDoc,
    bool restrictToTopIds = true,
  }) async {
    try {
      final startMs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('🔍 [PeopleRankingService] ========== INICIANDO getPeopleRanking ==========');
      debugPrint('   🗺️ selectedState: $selectedState');
      debugPrint('   📍 selectedLocality: $selectedLocality');
      debugPrint('   🔢 limit: $limit');

      // PASSO 1: Buscar Reviews com limite adaptativo (reduz 40-70% dos reads)
      debugPrint('\n📊 PASSO 1: Buscando Reviews...');
      
      // 🚀 OTIMIZAÇÃO: Universo menor e expansão só se bater no teto
      // Reviews: inicia direto em 50 para garantir máximo de perfis únicos
      int currentLimit = 50;
      final int targetUniqueUsers = limit;
      const int maxLimit = 50;

      QuerySnapshot<Map<String, dynamic>> reviewsSnapshot;

      var reviewsQuery = _firestore
          .collection('Reviews')
          .orderBy('created_at', descending: true)
          .limit(currentLimit);

      if (startAfterReviewDoc != null) {
        reviewsQuery = reviewsQuery.startAfterDocument(startAfterReviewDoc);
      }

      reviewsSnapshot = await reviewsQuery.get();

      debugPrint('   ✅ Reviews encontradas (tentativa 1): ${reviewsSnapshot.docs.length} (limit: $currentLimit)');

      if (reviewsSnapshot.docs.isEmpty) {
        debugPrint('   ⚠️ NENHUMA Review encontrada!');
        debugPrint('   💡 Verifique se a coleção Reviews existe no Firestore');
        return [];
      }

      // Log das primeiras 3 reviews
      debugPrint('   📋 Primeiras 3 Reviews:');
      for (var i = 0; i < reviewsSnapshot.docs.length && i < 3; i++) {
        final doc = reviewsSnapshot.docs[i];
        final data = doc.data();
        debugPrint('     ${i + 1}. ID: ${doc.id}');
        debugPrint('        - reviewee_id: ${data['reviewee_id']}');
        debugPrint('        - overall_rating: ${data['overall_rating']}');
        debugPrint('        - badges: ${data['badges']}');
        debugPrint('        - comment: ${data['comment']}');
      }

      Map<String, Map<String, dynamic>> aggregateReviews(
        QuerySnapshot<Map<String, dynamic>> snapshot,
      ) {
        final Map<String, Map<String, dynamic>> aggregated = {};

        for (var reviewDoc in snapshot.docs) {
          final data = reviewDoc.data();
          final revieweeId = data['reviewee_id'] as String?;

          if (revieweeId == null || revieweeId.isEmpty) continue;

          if (!aggregated.containsKey(revieweeId)) {
            aggregated[revieweeId] = {
              'totalReviews': 0,
              'sumRatings': 0.0,
              'badges_count': <String, int>{},
              'badgesTotal': 0,
              'lastReviewAtMs': 0,
              'ratings_breakdown': {
                'conversation': 0.0,
                'energy': 0.0,
                'participation': 0.0,
                'coexistence': 0.0,
              },
              'total_with_comment': 0,
            };
          }

          final stats = aggregated[revieweeId]!;

          stats['totalReviews'] = (stats['totalReviews'] as int) + 1;

          final rating = (data['overall_rating'] as num?)?.toDouble() ?? 0.0;
          stats['sumRatings'] = (stats['sumRatings'] as double) + rating;

          final createdAt = data['created_at'];
          if (createdAt is Timestamp) {
            final currentMs = createdAt.toDate().millisecondsSinceEpoch;
            final lastMs = stats['lastReviewAtMs'] as int? ?? 0;
            if (currentMs > lastMs) {
              stats['lastReviewAtMs'] = currentMs;
            }
          }

          final badges = data['badges'] as List?;
          if (badges != null) {
            final badgesCounts = stats['badges_count'] as Map<String, int>;
            for (var badge in badges) {
              final badgeName = badge.toString();
              badgesCounts[badgeName] = (badgesCounts[badgeName] ?? 0) + 1;
              stats['badgesTotal'] = (stats['badgesTotal'] as int) + 1;
            }
          }

          final criteriaRatings = data['criteria_ratings'] as Map?;
          if (criteriaRatings != null) {
            final breakdown = stats['ratings_breakdown'] as Map;
            breakdown['conversation'] = (breakdown['conversation'] as double) +
                ((criteriaRatings['conversation'] as num?)?.toDouble() ?? 0.0);
            breakdown['energy'] = (breakdown['energy'] as double) +
                ((criteriaRatings['energy'] as num?)?.toDouble() ?? 0.0);
            breakdown['participation'] = (breakdown['participation'] as double) +
                ((criteriaRatings['participation'] as num?)?.toDouble() ?? 0.0);
            breakdown['coexistence'] = (breakdown['coexistence'] as double) +
                ((criteriaRatings['coexistence'] as num?)?.toDouble() ?? 0.0);
          }

          final comment = data['comment'] as String?;
          if (comment != null && comment.isNotEmpty) {
            stats['total_with_comment'] = (stats['total_with_comment'] as int) + 1;
          }
        }

        return aggregated;
      }

      var aggregatedStats = aggregateReviews(reviewsSnapshot);

      int computeStats(Map<String, Map<String, dynamic>> aggregated) {
        int fiveStar = 0;
        for (var entry in aggregated.entries) {
          final stats = entry.value;
          final totalReviews = stats['totalReviews'] as int;
          final sumRatings = stats['sumRatings'] as double? ?? 0.0;
          final avg = totalReviews > 0 ? (sumRatings / totalReviews) : 0.0;
          stats['overallRating'] = avg;
          if (avg >= 4.95) fiveStar++;

          if (totalReviews > 0) {
            final breakdown = stats['ratings_breakdown'] as Map;
            breakdown['conversation'] =
                (breakdown['conversation'] as double) / totalReviews;
            breakdown['energy'] =
                (breakdown['energy'] as double) / totalReviews;
            breakdown['participation'] =
                (breakdown['participation'] as double) / totalReviews;
            breakdown['coexistence'] =
                (breakdown['coexistence'] as double) / totalReviews;
          }
        }
        return fiveStar;
      }

      int compareAggregate(
        Map<String, dynamic> a,
        Map<String, dynamic> b,
      ) {
        final aRating = (a['overallRating'] as num?)?.toDouble() ?? 0.0;
        final bRating = (b['overallRating'] as num?)?.toDouble() ?? 0.0;
        final ratingCmp = bRating.compareTo(aRating);
        if (ratingCmp != 0) return ratingCmp;

        final aTotal = (a['totalReviews'] as num?)?.toInt() ?? 0;
        final bTotal = (b['totalReviews'] as num?)?.toInt() ?? 0;
        final totalCmp = bTotal.compareTo(aTotal);
        if (totalCmp != 0) return totalCmp;

        final aBadges = (a['badgesTotal'] as num?)?.toInt() ?? 0;
        final bBadges = (b['badgesTotal'] as num?)?.toInt() ?? 0;
        final badgesCmp = bBadges.compareTo(aBadges);
        if (badgesCmp != 0) return badgesCmp;

        final aLast = (a['lastReviewAtMs'] as num?)?.toInt() ?? 0;
        final bLast = (b['lastReviewAtMs'] as num?)?.toInt() ?? 0;
        return bLast.compareTo(aLast);
      }

      // Calcular médias e overallRating para decidir expansão
      int fiveStarCount = computeStats(aggregatedStats);

      var uniqueReviewees = aggregatedStats.keys.toSet();
      final hasManyTies = fiveStarCount >= targetUniqueUsers;
      final hasSafetyMargin = uniqueReviewees.length >= targetUniqueUsers + 10;

      bool hasBoundaryTie = false;
      if (uniqueReviewees.length > targetUniqueUsers) {
        final sortedAggregates = aggregatedStats.values.toList()
          ..sort(compareAggregate);
        if (sortedAggregates.length > targetUniqueUsers) {
          final atLimit = sortedAggregates[targetUniqueUsers - 1];
          final next = sortedAggregates[targetUniqueUsers];
          hasBoundaryTie = compareAggregate(atLimit, next) == 0;
        }
      }

      if (!hasSafetyMargin &&
          reviewsSnapshot.docs.length == currentLimit &&
          (uniqueReviewees.length < targetUniqueUsers || hasManyTies || hasBoundaryTie) &&
          currentLimit < maxLimit) {
        currentLimit = maxLimit;
        debugPrint(
          '   🔄 Expansão: únicos=${uniqueReviewees.length}, ties=$fiveStarCount, limit=$currentLimit...',
        );

        var expandedQuery = _firestore
            .collection('Reviews')
            .orderBy('created_at', descending: true)
            .limit(currentLimit);

        if (startAfterReviewDoc != null) {
          expandedQuery = expandedQuery.startAfterDocument(startAfterReviewDoc);
        }

        reviewsSnapshot = await expandedQuery.get();
        debugPrint('   ✅ Reviews encontradas (tentativa 2): ${reviewsSnapshot.docs.length}');

        aggregatedStats = aggregateReviews(reviewsSnapshot);
        fiveStarCount = computeStats(aggregatedStats);
        uniqueReviewees = aggregatedStats.keys.toSet();
      }

      _lastReviewDoc = reviewsSnapshot.docs.isNotEmpty
          ? reviewsSnapshot.docs.last
          : null;
      
      // PASSO 2: Agregar reviews por reviewee_id
      debugPrint('\n👥 PASSO 2: Agregando reviews por usuário...');
      
      debugPrint('   ✅ Usuários com reviews: ${aggregatedStats.length}');
      debugPrint('   📋 Primeiros 3 agregados:');
      int logCount = 0;
      for (var entry in aggregatedStats.entries) {
        if (logCount >= 3) break;
        debugPrint('     ${logCount + 1}. UserId: ${entry.key}');
        debugPrint('        - totalReviews: ${entry.value['totalReviews']}');
        debugPrint('        - overallRating: ${entry.value['overallRating']}');
        debugPrint('        - badges_count: ${entry.value['badges_count']}');
        logCount++;
      }

      List<String> userIds;
      if (restrictToTopIds) {
        final sortedAggregates = aggregatedStats.entries.toList()
          ..sort((a, b) => compareAggregate(a.value, b.value));

        userIds = sortedAggregates
            .take(limit)
            .map((entry) => entry.key)
            .toList();
      } else {
        userIds = aggregatedStats.keys.toList();
      }

      // PASSO 3: Buscar dados dos usuários em lotes (OTIMIZADO: users_preview)
      debugPrint('\n👤 PASSO 3: Buscando dados dos usuários...');
      debugPrint('   🚀 Usando users_preview (~500 bytes vs 5-10KB completo)');

      Future<Map<String, Map<String, dynamic>>> fetchUsersData(
        List<String> ids,
      ) async {
        final Map<String, Map<String, dynamic>> result = {};
        int chunkIndex = 0;

        for (var i = 0; i < ids.length; i += 10) {
          final chunk = ids.skip(i).take(10).toList();
          chunkIndex++;

          debugPrint('   🔄 Chunk $chunkIndex: Buscando ${chunk.length} usuários...');

          final usersSnapshot = await _firestore
              .collection('users_preview')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          debugPrint('      ✅ Encontrados: ${usersSnapshot.docs.length} documentos');

          for (var doc in usersSnapshot.docs) {
            if (doc.exists && doc.data().isNotEmpty) {
              result[doc.id] = doc.data();
            }
          }
        }

        return result;
      }

      var usersData = await fetchUsersData(userIds);

      // Fallback: se topIds não retornaram dados, buscar todos os IDs agregados
      if (restrictToTopIds && usersData.isEmpty && aggregatedStats.isNotEmpty) {
        debugPrint('   ⚠️ Nenhum user_preview encontrado para topIds. Fallback para todos os IDs...');
        userIds = aggregatedStats.keys.toList();
        usersData = await fetchUsersData(userIds);
      }

      debugPrint('   ✅ Usuários carregados: ${usersData.length}/${userIds.length}');

      // PASSO 4: Montar ranking cruzando Stats + Users
      debugPrint('\n🏆 PASSO 4: Montando ranking...');
      
      final List<UserRankingModel> rankings = [];
      int skippedNoUser = 0;
      int skippedByCity = 0;

        final entries = restrictToTopIds
          ? userIds.map((id) => MapEntry(id, aggregatedStats[id]!))
          : aggregatedStats.entries;

      for (var entry in entries) {
        final userId = entry.key;
        final statsData = entry.value;
        final userData = usersData[userId];

        // Pular se não temos dados do usuário
        if (userData == null) {
          skippedNoUser++;
          continue;
        }

        // ✅ Filtrar usuários inativos (status != 'active')
        final userStatus = userData['status'] as String? ?? 'active';
        if (userStatus != 'active') {
          debugPrint('   ⏭️ Skipping inactive user: $userId (status: $userStatus)');
          skippedNoUser++;
          continue;
        }

        final userState = userData['state'] as String? ?? '';
        final userLocality = userData['locality'] as String? ?? '';
        
        // Filtrar por estado se especificado
        if (selectedState != null && 
            selectedState.isNotEmpty && 
            userState != selectedState) {
          skippedByCity++; // Reutilizar contador para simplicidade
          continue;
        }
        
        // Filtrar por cidade se especificado
        if (selectedLocality != null && 
            selectedLocality.isNotEmpty && 
            userLocality != selectedLocality) {
          skippedByCity++;
          continue;
        }

        // Criar modelo de ranking
        final ranking = UserRankingModel.fromData(
          userId: userId,
          userData: userData,
          statsData: statsData,
        );

        rankings.add(ranking);
        
        // Log dos primeiros 3
        if (rankings.length <= 3) {
          debugPrint('   ✅ #${rankings.length}: ${ranking.fullName}');
          debugPrint('      - Rating: ${ranking.overallRating}⭐');
          debugPrint('      - Reviews: ${ranking.totalReviews}');
          debugPrint('      - Locality: ${ranking.locality}');
          debugPrint('      - Badges: ${ranking.badgesCount.length}');
        }
      }

      debugPrint('\n📊 RESUMO:');
      debugPrint('   ✅ Rankings montados: ${rankings.length}');
      debugPrint('   ⚠️ Usuários sem dados: $skippedNoUser');
      debugPrint('   🔍 Filtrados por cidade: $skippedByCity');

      // PASSO 5: Ordenar por rating (melhor primeiro)
      debugPrint('\n🔄 PASSO 5: Ordenando por rating...');

      rankings.sort((a, b) {
        final ratingComparison = b.overallRating.compareTo(a.overallRating);
        if (ratingComparison != 0) return ratingComparison;

        final reviewsComparison = b.totalReviews.compareTo(a.totalReviews);
        if (reviewsComparison != 0) return reviewsComparison;

        final aBadges = a.badgesCount.values.fold<int>(0, (sum, v) => sum + v);
        final bBadges = b.badgesCount.values.fold<int>(0, (sum, v) => sum + v);
        final badgesComparison = bBadges.compareTo(aBadges);
        if (badgesComparison != 0) return badgesComparison;

        return 0;
      });

      // Limitar ao número solicitado
      final result = rankings.take(limit).toList();
      
      debugPrint('\n🏆 RANKING FINAL (Top ${result.length}):');
      for (var i = 0; i < result.length && i < 5; i++) {
        final r = result[i];
        debugPrint('   ${i + 1}º: ${r.fullName} - ${r.overallRating}⭐ (${r.totalReviews} reviews) - ${r.locality}');
      }
      
      debugPrint('========== FIM getPeopleRanking ==========\n');

      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      _lastMetrics = PeopleRankingMetrics(
        reviewsRead: reviewsSnapshot.docs.length,
        usersRead: usersData.length,
        uniqueReviewees: uniqueReviewees.length,
        limitUsed: currentLimit,
        durationMs: durationMs,
      );

      return result;
    } catch (error, stackTrace) {
      debugPrint('❌ ERRO CRÍTICO em getPeopleRanking:');
      debugPrint('   Error: $error');
      debugPrint('   StackTrace: $stackTrace');
      rethrow;
    }
  }

  Future<PeopleRankingPage> getPeopleRankingPage({
    String? selectedState,
    String? selectedLocality,
    int limit = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfterReviewDoc,
  }) async {
    final items = await getPeopleRanking(
      selectedState: selectedState,
      selectedLocality: selectedLocality,
      limit: limit,
      startAfterReviewDoc: startAfterReviewDoc,
    );

    return PeopleRankingPage(
      items: items,
      lastReviewDoc: _lastReviewDoc,
      metrics: _lastMetrics,
    );
  }

  /// Busca lista de cidades disponíveis (com reviews)
  /// 
  /// Retorna lista ordenada de cidades onde existem usuários avaliados
  Future<List<String>> getAvailableCities() async {
    try {
      debugPrint('🌆 [PeopleRankingService] ========== INICIANDO getAvailableCities ==========');

      final filters = await getRankingFilters();
      if (filters != null && filters.cities.isNotEmpty) {
        debugPrint('   ✅ Cidades carregadas via ranking_filters (${filters.cities.length})');
        return filters.cities;
      }

      // Buscar reviews para extrair reviewee_ids
      debugPrint('   📊 Buscando Reviews...');
      
      final reviewsSnapshot = await _firestore
          .collection('Reviews')
          .limit(500) // Limite razoável
          .get();

      debugPrint('   ✅ Reviews encontradas: ${reviewsSnapshot.docs.length}');

      if (reviewsSnapshot.docs.isEmpty) {
        debugPrint('   ⚠️ Nenhuma Review encontrada');
        return [];
      }

      // Extrair IDs únicos dos reviewees
      final userIds = reviewsSnapshot.docs
          .map((doc) => doc.data()['reviewee_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      debugPrint('   👥 Total de userIds com reviews: ${userIds.length}');

      // Buscar dados dos usuários em lotes
      final Set<String> cities = {};
      
      int chunkIndex = 0;
      for (var i = 0; i < userIds.length; i += 10) {
        final chunk = userIds.skip(i).take(10).toList();
        chunkIndex++;
        
        debugPrint('   🔄 Chunk $chunkIndex: Buscando ${chunk.length} usuários...');
        
        final usersSnapshot = await _firestore
          .collection('users_preview')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

        for (var doc in usersSnapshot.docs) {
          final locality = doc.data()['locality'] as String?;
          if (locality != null && locality.isNotEmpty) {
            cities.add(locality);
          }
        }
        
        debugPrint('      ✅ Cidades únicas até agora: ${cities.length}');
      }

      // Converter para lista ordenada
      final result = cities.toList()..sort();
      
      debugPrint('\n🌆 RESULTADO:');
      debugPrint('   ✅ Cidades encontradas: ${result.length}');
      if (result.isNotEmpty) {
        debugPrint('   📋 Primeiras 10: ${result.take(10).join(", ")}');
      }
      debugPrint('========== FIM getAvailableCities ==========\n');

      return result;
    } catch (error, stackTrace) {
      debugPrint('❌ ERRO em getAvailableCities:');
      debugPrint('   Error: $error');
      debugPrint('   StackTrace: $stackTrace');
      return [];
    }
  }

  /// Busca lista de estados disponíveis (com reviews)
  /// 
  /// Retorna lista ordenada de estados onde existem usuários avaliados
  Future<List<String>> getAvailableStates() async {
    try {
      debugPrint('🗺️ [PeopleRankingService] ========== INICIANDO getAvailableStates ==========');

      final filters = await getRankingFilters();
      if (filters != null && filters.states.isNotEmpty) {
        debugPrint('   ✅ Estados carregados via ranking_filters (${filters.states.length})');
        return filters.states;
      }

      // Buscar reviews para extrair reviewee_ids
      debugPrint('   📊 Buscando Reviews...');
      
      final reviewsSnapshot = await _firestore
          .collection('Reviews')
          .limit(500) // Limite razoável
          .get();

      debugPrint('   ✅ Reviews encontradas: ${reviewsSnapshot.docs.length}');

      if (reviewsSnapshot.docs.isEmpty) {
        debugPrint('   ⚠️ Nenhuma Review encontrada');
        return [];
      }

      // Extrair IDs únicos dos reviewees
      final userIds = reviewsSnapshot.docs
          .map((doc) => doc.data()['reviewee_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      debugPrint('   👥 Total de userIds com reviews: ${userIds.length}');

      // Buscar dados dos usuários em lotes
      final Set<String> states = {};
      
      int chunkIndex = 0;
      for (var i = 0; i < userIds.length; i += 10) {
        final chunk = userIds.skip(i).take(10).toList();
        chunkIndex++;
        
        debugPrint('   🔄 Chunk $chunkIndex: Buscando ${chunk.length} usuários...');
        
        final usersSnapshot = await _firestore
          .collection('users_preview')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

        for (var doc in usersSnapshot.docs) {
          final state = doc.data()['state'] as String?;
          if (state != null && state.isNotEmpty) {
            states.add(state);
          }
        }
        
        debugPrint('      ✅ Estados únicos até agora: ${states.length}');
      }

      // Converter para lista ordenada
      final result = states.toList()..sort();
      
      debugPrint('\n🗺️ RESULTADO:');
      debugPrint('   ✅ Estados encontrados: ${result.length}');
      if (result.isNotEmpty) {
        debugPrint('   📋 Estados: ${result.join(", ")}');
      }
      debugPrint('========== FIM getAvailableStates ==========\n');

      return result;
    } catch (error, stackTrace) {
      debugPrint('❌ ERRO em getAvailableStates:');
      debugPrint('   Error: $error');
      debugPrint('   StackTrace: $stackTrace');
      return [];
    }
  }
}

class PeopleRankingMetrics {
  const PeopleRankingMetrics({
    required this.reviewsRead,
    required this.usersRead,
    required this.uniqueReviewees,
    required this.limitUsed,
    required this.durationMs,
  });

  final int reviewsRead;
  final int usersRead;
  final int uniqueReviewees;
  final int limitUsed;
  final int durationMs;
}

class PeopleRankingPage {
  const PeopleRankingPage({
    required this.items,
    required this.lastReviewDoc,
    required this.metrics,
  });

  final List<UserRankingModel> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastReviewDoc;
  final PeopleRankingMetrics? metrics;
}
