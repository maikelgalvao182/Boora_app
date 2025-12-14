import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/list_drawer/list_drawer_controller.dart';
import 'package:partiu/features/home/presentation/widgets/people_button_controller.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/core/services/global_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Serviço responsável por inicializar dados globais antes do app abrir
class AppInitializerService {
  final MapViewModel mapViewModel;
  final PeopleRankingViewModel peopleRankingViewModel;
  final RankingViewModel locationsRankingViewModel;
  final ConversationsViewModel conversationsViewModel;

  AppInitializerService(
    this.mapViewModel,
    this.peopleRankingViewModel,
    this.locationsRankingViewModel,
    this.conversationsViewModel,
  );

  /// Executa toda a inicialização necessária
  /// 
  /// Fluxo de inicialização:
  /// 1. Inicializa cache de bloqueios (BlockService)
  /// 2. Inicializa ListDrawerController (eventos do usuário)
  /// 3. Pré-carrega avatar do usuário (HomeAppBar)
  /// 4. Pré-carrega PeopleButton (usuário recente + contagem)
  /// 5. Pré-carrega PeopleRankingViewModel (ranking e cidades)
  /// 6. Pré-carrega LocationsRankingViewModel (ranking de locais)
  /// 7. Pré-carrega ConversationsViewModel (conversas)
  /// 8. Pré-carrega participantes dos eventos do usuário (GroupInfo)
  /// 9. Pré-carrega pins (imagens dos markers)
  /// 10. Obtém localização do usuário
  /// 11. Carrega eventos próximos
  /// 12. Enriquece eventos com distância/disponibilidade/restrições de idade
  /// 13. PRÉ-CARREGA imagens dos markers (cache)
  /// 
  /// NOTA: Os markers pré-carregados servem apenas para popular o cache de imagens.
  /// O GoogleMapView regenerará os markers com os callbacks corretos.
  /// 
  /// ✅ RESTRIÇÕES DE IDADE: Pré-calculadas no _enrichEvents do MapViewModel
  /// para eliminar flash no botão do EventCard
  /// 
  /// Quando este método terminar, o mapa já estará pronto para exibir
  Future<void> initialize() async {
    try {
      debugPrint('🚀 [AppInitializer] Iniciando bootstrap do app...');
      
      // 1. Inicializa o cache de bloqueios
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        debugPrint('🔒 [AppInitializer] Inicializando BlockService...');
        await BlockService().initialize(currentUserId);
        debugPrint('✅ [AppInitializer] BlockService inicializado');
      } else {
        debugPrint('⚠️ [AppInitializer] BlockService não inicializado (usuário não autenticado)');
      }
      
      // 2. Pré-inicializa ListDrawerController (stream de eventos do usuário)
      debugPrint('📋 [AppInitializer] Inicializando ListDrawerController...');
      final drawerController = ListDrawerController();
      debugPrint('✅ [AppInitializer] ListDrawerController inicializado (stream ativo)');
      
      // 3. Pré-carrega avatar do usuário (HomeAppBar)
      if (currentUserId != null && currentUserId.isNotEmpty) {
        debugPrint('👤 [AppInitializer] Pré-carregando avatar do usuário (HomeAppBar)...');
        try {
          final userRepo = UserRepository();
          final currentUserData = await userRepo.getUserById(currentUserId);
          if (currentUserData != null) {
            // Avatar será carregado pelo StableAvatar usando o photoUrl
            debugPrint('✅ [AppInitializer] Avatar do usuário pré-carregado');
            debugPrint('   - Nome: ${currentUserData['full_name'] ?? 'N/A'}');
            debugPrint('   - Localização: ${currentUserData['locality'] ?? 'N/A'}, ${currentUserData['state'] ?? 'N/A'}');
          }
        } catch (e) {
          debugPrint('⚠️ [AppInitializer] Erro ao pré-carregar avatar: $e');
        }
      }
      
      // 4. Pré-carrega PeopleButton (usuário recente + contagem de pessoas próximas)
      debugPrint('🙋 [AppInitializer] Pré-carregando PeopleButton...');
      try {
        final peopleButtonController = NearbyButtonController();
        await peopleButtonController.loadData();
        debugPrint('✅ [AppInitializer] PeopleButton pré-carregado');
        debugPrint('   - Usuário recente: ${peopleButtonController.recentUser?.fullName ?? "Nenhum"}');
        debugPrint('   - Pessoas próximas: ${peopleButtonController.nearbyCount}');
      } catch (e) {
        debugPrint('⚠️ [AppInitializer] Erro ao pré-carregar PeopleButton: $e');
      }
      
      // 5. Pré-carrega PeopleRankingViewModel (ranking e cidades para filtro)
      debugPrint('👥 [AppInitializer] Pré-carregando PeopleRankingViewModel...');
      await peopleRankingViewModel.initialize();
      debugPrint('✅ [AppInitializer] PeopleRankingViewModel inicializado');
      debugPrint('   - Rankings: ${peopleRankingViewModel.peopleRankings.length}');
      debugPrint('   - Estados: ${peopleRankingViewModel.availableStates.length}');
      debugPrint('   - Cidades: ${peopleRankingViewModel.availableCities.length}');
      
      // 6. Pré-carrega LocationsRankingViewModel (ranking de locais e filtros)
      debugPrint('🏢 [AppInitializer] Pré-carregando LocationsRankingViewModel...');
      await locationsRankingViewModel.initialize();
      debugPrint('✅ [AppInitializer] LocationsRankingViewModel inicializado');
      debugPrint('   - Rankings: ${locationsRankingViewModel.locationRankings.length}');
      debugPrint('   - Estados: ${locationsRankingViewModel.availableStates.length}');
      debugPrint('   - Cidades: ${locationsRankingViewModel.availableCities.length}');
      
      // 7. Pré-carrega ConversationsViewModel (conversas, nomes e fotos)
      debugPrint('💬 [AppInitializer] Pré-carregando ConversationsViewModel...');
      await conversationsViewModel.preloadConversations();
      debugPrint('✅ [AppInitializer] ConversationsViewModel inicializado');
      debugPrint('   - Conversas: ${conversationsViewModel.wsConversations.length}');
      
      // 8. Pré-carrega participantes dos eventos do usuário (GroupInfo)
      if (currentUserId != null && currentUserId.isNotEmpty) {
        debugPrint('👥 [AppInitializer] Pré-carregando participantes dos eventos...');
        try {
          final appRepo = EventApplicationRepository();
          
          // Busca eventos criados pelo usuário (limitado aos 5 mais recentes)
          final myEventsSnapshot = await FirebaseFirestore.instance
              .collection('events')
              .where('createdBy', isEqualTo: currentUserId)
              .orderBy('createdAt', descending: true)
              .limit(5)
              .get();
              
          // Busca eventos que o usuário participa (limitado aos 5 mais recentes)
          final myApplicationsSnapshot = await FirebaseFirestore.instance
              .collection('EventApplications')
              .where('userId', isEqualTo: currentUserId)
              .where('status', whereIn: ['approved', 'autoApproved'])
              .orderBy('appliedAt', descending: true)
              .limit(5)
              .get();
              
          final eventIds = <String>{};
          
          // Adiciona IDs dos eventos criados
          for (var doc in myEventsSnapshot.docs) {
            eventIds.add(doc.id);
          }
          
          // Adiciona IDs dos eventos que participa
          for (var doc in myApplicationsSnapshot.docs) {
            final data = doc.data();
            if (data['eventId'] != null) {
              eventIds.add(data['eventId'] as String);
            }
          }
          
          debugPrint('   - Encontrados ${eventIds.length} eventos relevantes para pré-load');
          
          // Carrega participantes para cada evento em paralelo
          await Future.wait(eventIds.map((eventId) async {
            try {
              final participants = await appRepo.getParticipantsForEvent(eventId);
              
              // Salva no cache global (mesma chave usada pelo GroupInfoController)
              final cacheKey = 'event_participants_$eventId';
              GlobalCacheService.instance.set(cacheKey, participants, ttl: const Duration(minutes: 10));
              
              debugPrint('     - Evento $eventId: ${participants.length} participantes cacheados');
            } catch (e) {
              debugPrint('     ⚠️ Erro ao pré-carregar evento $eventId: $e');
            }
          }));
          
          debugPrint('✅ [AppInitializer] Participantes pré-carregados');
        } catch (e) {
          debugPrint('⚠️ [AppInitializer] Erro ao pré-carregar participantes: $e');
        }
      }

      // 9. Inicializa o ViewModel (preload de pins + carrega eventos)
      // O initialize() do ViewModel já chama loadNearbyEvents() internamente
      // que também gera os markers (populando o cache de imagens)
      await mapViewModel.initialize();
      
      debugPrint('✅ [AppInitializer] Bootstrap completo!');
      debugPrint('📊 [AppInitializer] Eventos carregados: ${mapViewModel.events.length}');
      debugPrint('📍 [AppInitializer] Markers gerados (cache): ${mapViewModel.googleMarkers.length}');
      debugPrint('🗺️ [AppInitializer] Mapa pronto: ${mapViewModel.mapReady}');
      debugPrint('💬 [AppInitializer] Conversas pré-carregadas: ${conversationsViewModel.wsConversations.length}');
      debugPrint('ℹ️ [AppInitializer] Markers serão regenerados com callbacks no GoogleMapView');
      
    } catch (e, stackTrace) {
      debugPrint('❌ [AppInitializer] Erro durante inicialização: $e');
      debugPrint('Stack trace: $stackTrace');
      // Não lançar erro - deixar app abrir mesmo com falha
      // O ViewModel tentará carregar novamente quando o mapa estiver pronto
    }
  }
}
