import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/models/activity_notification_types.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';
import 'package:partiu/features/profile/repositories/profile_view_repository.dart';

/// TRIGGER ESPECIAL: Visualizações de perfil agregadas
/// 
/// Este trigger é diferente dos outros pois:
/// 1. Não dispara individualmente
/// 2. Agrupa múltiplas visualizações
/// 3. Usa debouncing para evitar spam
/// 
/// Comportamento:
/// - Acumula visualizações ao longo do tempo
/// - Dispara notificação apenas se count > 0
/// - Marca visualizações como "notified" após enviar
/// 
/// Notificação: "{count} pessoas visualizaram seu perfil ✨"
/// 
/// Exemplo:
/// "5 viajantes perto de você visualizaram seu perfil ✨"
/// 
/// Como usar:
/// ```dart
/// // Opção 1: Manualmente (em algum lugar do app)
/// await profileViewTrigger.processAndNotify(userId: currentUserId);
/// 
/// // Opção 2: Cloud Function agendada (recomendado)
/// // Roda a cada 15 minutos processando todos os usuários
/// ```
class ProfileViewAggregationTrigger extends BaseActivityTrigger {
  ProfileViewAggregationTrigger({
    required super.notificationRepository,
    required super.firestore,
    ProfileViewRepository? profileViewRepository,
  }) : _profileViewRepository = profileViewRepository ?? ProfileViewRepository();

  final ProfileViewRepository _profileViewRepository;

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    // Este trigger não usa ActivityModel
    // Use processAndNotify() diretamente
    throw UnimplementedError(
      'ProfileViewAggregationTrigger não usa execute(). Use processAndNotify().',
    );
  }

  /// Processa visualizações não notificadas e envia notificação agregada
  /// 
  /// Fluxo:
  /// 1. Busca visualizações não notificadas
  /// 2. Se count > 0, cria notificação agregada
  /// 3. Marca visualizações como notificadas
  /// 
  /// @param userId - ID do usuário que recebeu as visualizações
  /// @param minimumCount - Mínimo de visualizações para disparar (padrão: 1)
  Future<void> processAndNotify({
    required String userId,
    int minimumCount = 1,
  }) async {
    print('👁️ [ProfileViewAggregationTrigger.processAndNotify] INICIANDO');
    print('👁️ [ProfileViewAggregationTrigger.processAndNotify] UserId: $userId');
    print('👁️ [ProfileViewAggregationTrigger.processAndNotify] MinimumCount: $minimumCount');
    
    try {
      // 1. Busca visualizações não notificadas
      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] Buscando visualizações não notificadas...');
      final unnotifiedViews = await _profileViewRepository.fetchUnnotifiedViews(
        userId: userId,
      );

      final count = unnotifiedViews.length;
      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] Visualizações não notificadas: $count');

      // 2. Verifica se atinge o mínimo
      if (count < minimumCount) {
        print('⚠️ [ProfileViewAggregationTrigger.processAndNotify] Contagem abaixo do mínimo ($count < $minimumCount)');
        return;
      }

      // 3. Extrai dados relevantes
      final viewerIds = unnotifiedViews.map((v) => v.viewerId).toList();
      final lastViewedAt = unnotifiedViews.isNotEmpty
          ? unnotifiedViews.first.viewedAt
          : DateTime.now();

      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] ViewerIds: ${viewerIds.join(", ")}');
      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] LastViewedAt: $lastViewedAt');
      
      // 4. Monta parâmetros da notificação
      final params = {
        'count': count.toString(),
        'lastViewedAt': _formatRelativeTime(lastViewedAt),
        'viewerIds': viewerIds.join(','), // Para analytics
      };
      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] Params: $params');

      // 5. Cria notificação agregada
      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] Criando notificação agregada...');
      await createNotification(
        receiverId: userId,
        type: ActivityNotificationTypes.profileViewsAggregated,
        params: params,
        relatedId: null, // Não há entidade específica
      );

      // 6. Marca visualizações como notificadas
      final viewIds = unnotifiedViews
          .where((v) => v.id != null)
          .map((v) => v.id!)
          .toList();

      print('👁️ [ProfileViewAggregationTrigger.processAndNotify] Marcando ${viewIds.length} visualizações como notificadas...');
      await _profileViewRepository.markAsNotified(viewIds);

      print('✅ [ProfileViewAggregationTrigger.processAndNotify] CONCLUÍDO - $count visualizações notificadas');
    } catch (e, stackTrace) {
      print('❌ [ProfileViewAggregationTrigger.processAndNotify] ERRO: $e');
      print('❌ [ProfileViewAggregationTrigger.processAndNotify] StackTrace: $stackTrace');
    }
  }

  /// Processa todos os usuários com visualizações pendentes
  /// 
  /// Útil para Cloud Function agendada que roda periodicamente
  /// 
  /// Limitações:
  /// - Processa no máximo [batchSize] usuários por execução
  /// - Requer índice composto no Firestore
  Future<void> processAllUsers({
    int batchSize = 50,
    int minimumCount = 1,
  }) async {
    try {
      // Busca usuários únicos com visualizações pendentes
      final snapshot = await firestore
          .collection('ProfileViews')
          .where('notified', isEqualTo: false)
          .limit(batchSize * 10) // Busca mais docs pois podem ter duplicatas
          .get();

      if (snapshot.docs.isEmpty) {
        print('[ProfileViewAggregationTrigger] Nenhuma visualização pendente');
        return;
      }

      // Extrai userIds únicos
      final userIds = <String>{};
      for (final doc in snapshot.docs) {
        final viewedUserId = doc.data()['viewedUserId'] as String?;
        if (viewedUserId != null) {
          userIds.add(viewedUserId);
        }
      }

      print('[ProfileViewAggregationTrigger] Processando ${userIds.length} usuários');

      // Processa cada usuário
      int notificationsSent = 0;
      for (final userId in userIds.take(batchSize)) {
        await processAndNotify(
          userId: userId,
          minimumCount: minimumCount,
        );
        notificationsSent++;
      }

      print('[ProfileViewAggregationTrigger] $notificationsSent notificações enviadas');
    } catch (e) {
      print('[ProfileViewAggregationTrigger] Erro ao processar todos: $e');
    }
  }

  /// Formata timestamp relativo (ex: "há 5 minutos")
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'agora mesmo';
    } else if (difference.inMinutes < 60) {
      return 'há ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'há ${difference.inHours}h';
    } else {
      return 'há ${difference.inDays}d';
    }
  }

  /// Estatísticas de visualizações (útil para debugging)
  Future<Map<String, dynamic>> getStats({required String userId}) async {
    try {
      final unnotifiedViews = await _profileViewRepository.fetchUnnotifiedViews(
        userId: userId,
      );

      final last24h = DateTime.now().subtract(const Duration(hours: 24));
      final recentViews = unnotifiedViews
          .where((v) => v.viewedAt.isAfter(last24h))
          .toList();

      return {
        'total_unnotified': unnotifiedViews.length,
        'last_24h': recentViews.length,
        'oldest_view': unnotifiedViews.isNotEmpty
            ? unnotifiedViews.last.viewedAt.toIso8601String()
            : null,
        'newest_view': unnotifiedViews.isNotEmpty
            ? unnotifiedViews.first.viewedAt.toIso8601String()
            : null,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
