import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/common/state/app_state.dart';

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

  /// Verifica se o usuário atual é VIP (necessário para ver visitas)
  bool _isCurrentUserVip() {
    final user = AppState.currentUser.value;
    if (user == null) return false;
    return user.hasActiveVip;
  }

  /// Busca o número de visitas de um usuário
  /// ⚠️ NOTA: Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
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

    // 🔒 Verifica se o usuário é VIP antes de tentar a query
    // Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
    if (!_isCurrentUserVip()) {
      if (kDebugMode) {
        debugPrint('🔒 [VisitsService] Usuário não é VIP, retornando 0');
      }
      _cachedVisitsCount = 0;
      _hasLoadedOnce = true;
      return 0;
    }

    try {
      // 🚀 Mudança para AggregateQuery: Conta documentos reais na coleção ProfileVisits
      // Filtra por visitas recentes (últimos 7 dias) para coincidir com a lista
      
      final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
      
      final snapshot = await _firestore
          .collection('ProfileVisits')
          .where('visitedUserId', isEqualTo: userId)
          .where('visitedAt', isGreaterThan: Timestamp.fromDate(cutoffDate))
          .orderBy('visitedAt', descending: true)
          .count()
          .get();

      final count = snapshot.count ?? 0;

      if (kDebugMode) {
        debugPrint('📊 [VisitsService] Count (Aggregate): $count');
      }
      
      _cachedVisitsCount = count;
      _hasLoadedOnce = true;
      return count;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [VisitsService] Erro ao contar visitas: $e');
      }
      // Retorna 0 em caso de erro, ou mantém cache se preferir
      // Mantendo lógica original de zerar cache em erro, mas aqui talvez seja melhor manter o cache antigo se houver
      return _cachedVisitsCount;
    }
  }

  /// Stream simplificado para observar o número de visitas
  /// Retorna stream que emite o count sempre que a lista de visitors muda
  /// ⚠️ NOTA: Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
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

    // 🔒 Verifica se o usuário é VIP antes de tentar a query
    // Apenas VIPs podem ver quem visitou seu perfil (regra Firestore)
    if (!_isCurrentUserVip()) {
      if (kDebugMode) {
        debugPrint('🔒 [VisitsService] Usuário não é VIP, yielding 0');
      }
      _cachedVisitsCount = 0;
      _hasLoadedOnce = true;
      yield 0;
      return;
    }

    // Emite o valor inicial
    if (kDebugMode) {
      debugPrint('📤 [VisitsService] Emitindo valor inicial via getUserVisitsCount...');
    }
    yield await getUserVisitsCount(userId);

    // Escuta mudanças na coleção REAL de visitas (ProfileVisits)
    // Usamos limit(1) pois só queremos o trigger de mudança da collection
    // Se documentos são DELETADOS, o snapshot também é disparado se mudar o resultado da query?
    // snapshots() em uma query emite quando o conjunto de resultados muda (add/remove/modify).
    // Mas se usamos limit(1), pode não disparar se a mudança for na posição 50.
    // O ideal seria ouvir metadata changes ou sem limite se o custo permitir, mas ProfileVisits pode ser grande.
    // Como queremos só saber se "perdemos" ou "ganhamos" visitas, o count é o que importa.
    // Mas Firestore não tem "stream de count" nativo barato.
    // Alternativa: Ouvir ProfileVisits limit(1) order by visitedAt desc.
    // Se entrar visita nova, o topo muda -> dispara event.
    // Se deletar visita antiga (expiração), o topo NÃO muda -> NÃO dispara event.
    
    // CORREÇÃO: Se a deleção é automática pelo backend, o cliente não recebe notificação a menos que afete o snapshot observado.
    // Se monitoramos limit(1), só vemos mudanças no visitante mais recente.
    // Para ver deleções, precisamos recarregar periodicamente ou quando o usuário entra na tela.
    // Mas o usuário especificamente reclamou que o número "continua mostrando".
    // Talvez o problema anterior fosse usar uma Cloud Function que retornava um "totalVisits" incremental que NUNCA diminuia.
    // Agora usando count() direto, pelo menos ao entrar na tela (getUserVisitsCount) o numero estará correto.
    // Para manter atualizado em tempo real com deleções em massa, é difícil sem polling ou stream de tudo.
    // Vamos manter o stream no topo (novas visitas) e adicionar um timer de refresh periódico ou confiar que ao navegar o usuário atualiza.
    // O watcher abaixo garante que NOVAS visitas atualizem o count.
    
    await for (final _ in _firestore
        .collection('ProfileVisits')
        .where('visitedUserId', isEqualTo: userId)
        .orderBy('visitedAt', descending: true)
        .limit(1)
        .snapshots()) {
      
      if (kDebugMode) {
        debugPrint('🔄 [VisitsService] Alteração detectada em ProfileVisits (topo)');
      }
      
      // Recalcula o total usando count() aggregation
      yield await getUserVisitsCount(userId);
    }
  }
}