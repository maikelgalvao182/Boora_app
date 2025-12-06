import 'package:cloud_firestore/cloud_firestore.dart';

/// CAMADA 1 — Cálculo de Afinidade entre Usuários
///
/// Responsável por:
/// - Buscar interesses do criador da atividade
/// - Buscar interesses de usuários candidatos (em batch)
/// - Calcular interseção de interesses
/// - Ordenar usuários por relevância (mais interesses em comum primeiro)
///
/// Retorno principal:
///   Map<userId, List<String>> → interesses em comum por usuário
///
/// REGRA DE NEGÓCIO CRÍTICA:
/// - Apenas usuários COM pelo menos 1 interesse em comum recebem notificação
/// - Isso reduz SPAM e aumenta relevância
class UserAffinityService {
  final FirebaseFirestore _firestore;

  /// Limite de IDs por batch de consulta (`whereIn` suporta até 10 valores)
  static const int _batchSize = 10;

  UserAffinityService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // ===========================================================================
  // API PRINCIPAL
  // ===========================================================================

  /// Calcula mapa de afinidade entre o criador e uma lista de usuários candidatos.
  ///
  /// Fluxo:
  /// 1. Busca interesses do criador
  /// 2. Busca interesses dos candidatos em batch
  /// 3. Calcula interseção (interesses em comum)
  /// 4. Retorna apenas usuários com pelo menos 1 interesse em comum
  Future<Map<String, List<String>>> calculateAffinityMap({
    required String creatorId,
    required List<String> candidateUserIds,
  }) async {
    print('\n💖 [Affinity] calculateAffinityMap() — INICIANDO');
    print('👤 Criador: $creatorId');
    print('👥 Candidatos: ${candidateUserIds.length}');

    if (candidateUserIds.isEmpty) {
      print('⚠️ [Affinity] Nenhum candidato fornecido');
      return {};
    }

    try {
      // 1. Interesses do criador
      final creatorInterests = await _getUserInterests(creatorId);
      final creatorSet = creatorInterests.toSet();

      print('🎯 [Affinity] Interesses do criador: '
          '${creatorSet.length} → $creatorSet');

      if (creatorSet.isEmpty) {
        print('⚠️ [Affinity] Criador sem interesses cadastrados. '
            'Nenhuma notificação será enviada por afinidade.');
        return {};
      }

      // 2. Interesses dos candidatos (em batch)
      final candidatesInterestsMap =
          await _getManyUserInterests(candidateUserIds);

      if (candidatesInterestsMap.isEmpty) {
        print('⚠️ [Affinity] Nenhum candidato com interesses encontrados');
        return {};
      }

      // 3. Calcular interseção
      final Map<String, List<String>> affinityMap = {};
      int usersWithAffinity = 0;

      candidatesInterestsMap.forEach((userId, interests) {
        if (interests.isEmpty) {
          print('⚠️ [Affinity] Usuário $userId sem interesses cadastrados');
          return;
        }

        final candidateSet = interests.toSet();
        final common = creatorSet.intersection(candidateSet).toList();

        if (common.isNotEmpty) {
          affinityMap[userId] = common;
          usersWithAffinity++;
        } else {
          print('⚠️ [Affinity] Usuário $userId sem interesses em comum com o criador');
          print('   - Criador: $creatorSet');
          print('   - Usuário: $candidateSet');
        }
      });

      print('✅ [Affinity] CONCLUÍDO');
      print('📊 Usuários com afinidade: '
          '$usersWithAffinity / ${candidateUserIds.length}');

      return affinityMap;
    } catch (e, stackTrace) {
      print('❌ [Affinity] ERRO em calculateAffinityMap: $e');
      print('❌ StackTrace: $stackTrace');
      return {};
    }
  }

  /// Ordena o mapa de afinidade por relevância
  /// (mais interesses em comum primeiro).
  Map<String, List<String>> sortByRelevance(
    Map<String, List<String>> affinityMap,
  ) {
    final entries = affinityMap.entries.toList()
      ..sort(
        (a, b) => b.value.length.compareTo(a.value.length),
      );

    return Map.fromEntries(entries);
  }

  /// Calcula um *score* de afinidade (0.0 a 1.0) entre dois usuários.
  ///
  /// Usa Jaccard similarity:
  /// score = (interesses em comum) / (interesses únicos combinados)
  Future<double> calculateAffinityScore({
    required String userId1,
    required String userId2,
  }) async {
    try {
      final interests1 = (await _getUserInterests(userId1)).toSet();
      final interests2 = (await _getUserInterests(userId2)).toSet();

      if (interests1.isEmpty || interests2.isEmpty) return 0.0;

      final common = interests1.intersection(interests2).length;
      final union = interests1.union(interests2).length;

      if (union == 0) return 0.0;

      return common / union;
    } catch (e) {
      print('❌ [Affinity] ERRO em calculateAffinityScore: $e');
      return 0.0;
    }
  }

  /// Busca usuários que possuem pelo menos um dos [interests].
  ///
  /// Usa `arrayContainsAny` (limite de 10 valores).
  Future<List<String>> findUsersWithInterests({
    required List<String> interests,
    int limit = 100,
  }) async {
    if (interests.isEmpty) return [];

    try {
      final toQuery = interests.take(10).toList();

      print('🔍 [Affinity] Buscando usuários com interesses: $toQuery');

      final snap = await _firestore
          .collection('Users')
          .where('interests', arrayContainsAny: toQuery)
          .limit(limit)
          .get();

      final ids = snap.docs.map((d) => d.id).toList();

      print('✅ [Affinity] Encontrados ${ids.length} usuários com interesses');
      return ids;
    } catch (e) {
      print('❌ [Affinity] ERRO em findUsersWithInterests: $e');
      return [];
    }
  }

  /// Retorna apenas os usuários que têm afinidade com o criador
  /// (pelo menos 1 interesse em comum).
  Future<List<String>> filterUsersWithAffinity({
    required String creatorId,
    required List<String> candidateUserIds,
  }) async {
    final affinityMap = await calculateAffinityMap(
      creatorId: creatorId,
      candidateUserIds: candidateUserIds,
    );

    return affinityMap.keys.toList();
  }

  /// Retorna os top N usuários com maior afinidade com [userId].
  Future<List<String>> getTopAffinityUsers({
    required String userId,
    required List<String> candidateUserIds,
    int topN = 10,
  }) async {
    final affinityMap = await calculateAffinityMap(
      creatorId: userId,
      candidateUserIds: candidateUserIds,
    );

    final sorted = sortByRelevance(affinityMap);
    return sorted.keys.take(topN).toList();
  }

  /// Estatísticas de afinidade para debug / analytics.
  Future<Map<String, dynamic>> getAffinityStats({
    required String creatorId,
    required List<String> candidateUserIds,
  }) async {
    final affinityMap = await calculateAffinityMap(
      creatorId: creatorId,
      candidateUserIds: candidateUserIds,
    );

    if (affinityMap.isEmpty) {
      return {
        'totalCandidates': candidateUserIds.length,
        'usersWithAffinity': 0,
        'affinityRate': 0.0,
        'avgCommonInterests': 0.0,
        'maxCommonInterests': 0,
        'topInterests': <String, int>{},
      };
    }

    final counts = affinityMap.values.map((list) => list.length).toList();
    final totalCommon = counts.reduce((a, b) => a + b);
    final maxCommon = counts.reduce((a, b) => a > b ? a : b);

    return {
      'totalCandidates': candidateUserIds.length,
      'usersWithAffinity': affinityMap.length,
      'affinityRate': affinityMap.length / candidateUserIds.length,
      'avgCommonInterests': totalCommon / affinityMap.length,
      'maxCommonInterests': maxCommon,
      'topInterests': _getTopCommonInterests(affinityMap),
    };
  }

  // ===========================================================================
  // HELPERS PRIVADOS — FIRESTORE
  // ===========================================================================

  /// Busca interesses de UM usuário.
  ///
  /// Estrutura esperada no Firestore:
  /// Users/{userId} {
  ///   interests: ['Café', 'Viagem', 'Música']
  /// }
  Future<List<String>> _getUserInterests(String userId) async {
    try {
      final doc = await _firestore.collection('Users').doc(userId).get();

      if (!doc.exists) {
        return [];
      }

      final data = doc.data();
      if (data == null) return [];

      final rawInterests =
          data['interests'] as List<dynamic>? ??
          data['interest'] as List<dynamic>? ??
          <dynamic>[];

      return rawInterests.map((e) => e.toString()).toList();
    } catch (e) {
      print('❌ [Affinity] ERRO em _getUserInterests($userId): $e');
      return [];
    }
  }

  /// Busca interesses de VÁRIOS usuários usando batches com `whereIn`.
  ///
  /// Retorna:
  ///   Map<userId, List<String>>
  Future<Map<String, List<String>>> _getManyUserInterests(
    List<String> userIds,
  ) async {
    final Map<String, List<String>> result = {};

    if (userIds.isEmpty) return result;

    // Quebra lista em chunks de até _batchSize IDs
    for (var i = 0; i < userIds.length; i += _batchSize) {
      final chunk = userIds.skip(i).take(_batchSize).toList();

      try {
        final snap = await _firestore
            .collection('Users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final rawInterests =
              data['interests'] as List<dynamic>? ??
              data['interest'] as List<dynamic>? ??
              <dynamic>[];

          result[doc.id] = rawInterests.map((e) => e.toString()).toList();
        }
      } catch (e) {
        print('❌ [Affinity] ERRO em _getManyUserInterests chunk: $e');
      }
    }

    return result;
  }

  /// Identifica os interesses mais comuns entre todos os matches.
  Map<String, int> _getTopCommonInterests(
    Map<String, List<String>> affinityMap,
  ) {
    final Map<String, int> counts = {};

    for (final interests in affinityMap.values) {
      for (final interest in interests) {
        counts[interest] = (counts[interest] ?? 0) + 1;
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Top 5 interesses mais comuns
    return Map.fromEntries(sorted.take(5));
  }
}
