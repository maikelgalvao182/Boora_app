import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Serviço para gerenciar visitas do perfil
class VisitsService {
  VisitsService._();
  
  static final VisitsService _instance = VisitsService._();
  static VisitsService get instance => _instance;

  /// Cache do número de visitas
  int _cachedVisitsCount = 0;
  int get cachedVisitsCount => _cachedVisitsCount;

  /// Flag para indicar se já carregou pelo menos uma vez
  bool _hasLoadedOnce = false;
  bool get hasLoadedOnce => _hasLoadedOnce;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Busca o número de visitas de um usuário
  Future<int> getUserVisitsCount(String userId) async {
    if (kDebugMode) {
      debugPrint('🔍 [VisitsService] getUserVisitsCount iniciado para userId: $userId');
    }
    
    if (userId.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ [VisitsService] userId vazio, retornando 0');
      }
      _cachedVisitsCount = 0;
      return 0;
    }

    try {
      if (kDebugMode) {
        debugPrint('📞 [VisitsService] Chamando Cloud Function getProfileVisitsCount...');
      }
      final result = await _functions.httpsCallable('getProfileVisitsCount').call({
        'userId': userId,
      });

      if (kDebugMode) {
        debugPrint('✅ [VisitsService] Cloud Function respondeu: ${result.data}');
      }
      
      final data = result.data;
      final count = (data is Map && data['count'] is num)
          ? (data['count'] as num).toInt()
          : 0;

      if (kDebugMode) {
        debugPrint('📊 [VisitsService] Count extraído: $count (cache atualizado)');
      }
      _cachedVisitsCount = count;
      _hasLoadedOnce = true;
      return count;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [VisitsService] FirebaseFunctionsException: ${e.code} - ${e.message}');
      }
      _cachedVisitsCount = 0;
      _hasLoadedOnce = true;
      return 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [VisitsService] Erro inesperado: $e');
      }
      _cachedVisitsCount = 0;
      _hasLoadedOnce = true;
      return 0;
    }
  }

  /// Stream simplificado para observar o número de visitas
  /// Retorna stream que emite o count sempre que a lista de visitors muda
  Stream<int> watchUserVisitsCount(String userId) async* {
    if (kDebugMode) {
      debugPrint('🎧 [VisitsService] watchUserVisitsCount iniciado para userId: $userId');
    }
    
    if (userId.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ [VisitsService] userId vazio no stream, yielding 0');
      }
      _cachedVisitsCount = 0;
      yield 0;
      return;
    }

    // Emite o valor inicial via Cloud Function (funciona mesmo quando ProfileVisits é VIP-only).
    if (kDebugMode) {
      debugPrint('📤 [VisitsService] Emitindo valor inicial via getUserVisitsCount...');
    }
    final initialCount = await getUserVisitsCount(userId);
    if (kDebugMode) {
      debugPrint('📤 [VisitsService] Valor inicial emitido: $initialCount');
    }
    yield initialCount;

    // Usa ProfileViews (legível pelo dono do perfil sem exigir VIP) como gatilho de atualização.
    // Quando entra uma nova view, recalcula o contador (que vem de ProfileVisits.visitCount).
    if (kDebugMode) {
      debugPrint('👀 [VisitsService] Iniciando listener de ProfileViews...');
    }
    bool isFirstSnapshot = true;
    await for (final snapshot in _firestore
        .collection('ProfileViews')
        .where('viewedUserId', isEqualTo: userId)
        .orderBy('viewedAt', descending: true)
        .limit(1)
        .snapshots()) {
      if (kDebugMode) {
        debugPrint('🔄 [VisitsService] ProfileViews snapshot recebido (${snapshot.docs.length} docs)');
      }
      
      if (isFirstSnapshot) {
        if (kDebugMode) {
          debugPrint('⏭️ [VisitsService] Pulando primeiro snapshot (inicial)');
        }
        isFirstSnapshot = false;
        continue;
      }

      if (kDebugMode) {
        debugPrint('🔄 [VisitsService] Nova view detectada, recalculando count...');
      }
      final count = await getUserVisitsCount(userId);
      if (kDebugMode) {
        debugPrint('📤 [VisitsService] Novo count emitido: $count');
      }
      yield count;
    }
  }
}