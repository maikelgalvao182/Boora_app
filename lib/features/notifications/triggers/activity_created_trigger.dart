import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/services/notification_orchestrator.dart';
import 'package:partiu/features/notifications/services/notification_targeting_service.dart';
import 'package:partiu/features/notifications/triggers/base_activity_trigger.dart';

/// TRIGGER 1: Nova atividade criada no raio do usuário (30km)
/// 
/// NOVA ARQUITETURA EM CAMADAS:
/// 
/// Trigger → TargetingService → (GeoIndex + Affinity) → Orchestrator → Firestore
/// 
/// O trigger agora é MINIMALISTA:
/// - NÃO faz cálculo geográfico
/// - NÃO busca interesses
/// - NÃO cria texto de notificação
/// - NÃO cria documento Firestore diretamente
/// 
/// Ele apenas:
/// 1. Busca targets via TargetingService
/// 2. Busca dados do criador
/// 3. Delega criação ao Orchestrator
class ActivityCreatedTrigger extends BaseActivityTrigger {
  final NotificationTargetingService _targetingService;
  final NotificationOrchestrator _orchestrator;

  const ActivityCreatedTrigger({
    required super.notificationRepository,
    required super.firestore,
    required NotificationTargetingService targetingService,
    required NotificationOrchestrator orchestrator,
  })  : _targetingService = targetingService,
        _orchestrator = orchestrator;

  @override
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  ) async {
    print('\n🎯 [ActivityCreatedTrigger] ====================================');
    print('🎯 Activity: ${activity.id} - ${activity.name} ${activity.emoji}');
    print('🎯 Criador: ${activity.createdBy}');
    print('🎯 Localização: (${activity.latitude}, ${activity.longitude})');
    
    try {
      // 1. Buscar targets (geo + afinidade) via TargetingService
      print('🎯 Buscando targets via TargetingService...');
      final affinityMap = await _targetingService.getUsersForActivityCreated(activity);
      
      if (affinityMap.isEmpty) {
        print('⚠️ Nenhum usuário com afinidade encontrado');
        print('🎯 [ActivityCreatedTrigger] ====================================\n');
        return;
      }

      print('✅ Targets encontrados: ${affinityMap.length}');

      // 2. Buscar dados do criador
      print('🎯 Buscando dados do criador...');
      final creatorInfo = await getUserInfo(activity.createdBy);
      print('✅ Criador: ${creatorInfo['fullName']}');

      // Converter para UserInfo
      final creator = UserInfo(
        id: activity.createdBy,
        fullName: creatorInfo['fullName'] ?? 'Alguém',
        photoUrl: creatorInfo['photoUrl'],
      );

      // 3. Delegar criação ao Orchestrator (batch writes otimizados)
      print('🎯 Delegando criação ao Orchestrator...');
      await _orchestrator.createActivityCreatedNotifications(
        activity: activity,
        affinityMap: affinityMap,
        creator: creator,
      );

      print('✅ [ActivityCreatedTrigger] CONCLUÍDO - ${affinityMap.length} notificações criadas');
      print('🎯 [ActivityCreatedTrigger] ====================================\n');

    } catch (e, stackTrace) {
      print('❌ [ActivityCreatedTrigger] ERRO: $e');
      print('❌ StackTrace: $stackTrace');
      print('🎯 [ActivityCreatedTrigger] ====================================\n');
      rethrow;
    }
  }
}
