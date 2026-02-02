import 'dart:async';
import 'dart:math' show cos;

import 'package:flutter/painting.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/features/home/presentation/services/google_event_marker_service.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/utils/app_logger.dart';

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

  Future<({dynamic location, dynamic events})?> _waitForInitialMapSnapshot({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final location = mapViewModel.lastLocation;
      final events = mapViewModel.events;

      if (location != null && events.isNotEmpty) {
        return (location: location, events: events);
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    return null;
  }

  /// Executa toda a inicialização necessária (LEGADO)
  ///
  /// ⚠️ Preferir:
  /// - [initializeCritical] no Splash (rápido)
  /// - [warmupAfterFirstFrame] na Home (background)
  /// 
  /// Fluxo de inicialização:
  /// 1. Inicializa cache de bloqueios (BlockService)
  /// 2. Inicializa ListDrawerController (eventos do usuário)
  /// 3. Pré-carrega avatar do usuário (HomeAppBar)
  /// 4. (Opcional) Pré-carrega rankings (pessoas/locais)
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
  /// ✅ FIND PEOPLE: Lista pré-carregada com avatares no UserStore
  /// para eliminar shimmer ao abrir a tela FindPeopleScreen
  /// 
  /// Quando este método terminar, o mapa já estará pronto para exibir
  Future<void> initialize() async {
    await initializeCritical();
    await warmupAfterFirstFrame();
  }

  /// Inicialização CRÍTICA (deve rodar no Splash)
  ///
  /// Objetivo: reduzir tempo do splash removendo o trabalho pesado.
  /// Mantém apenas o essencial para a Home abrir sem travar.
  Future<void> initializeCritical() async {
    try {
      AppLogger.info('Iniciando bootstrap do app...', tag: 'INIT');
      
      // 🔒 Configura limite global do ImageCache (evita memory leak com preload)
      // Máximo 200 imagens ou 50MB em memória
      PaintingBinding.instance.imageCache
        ..maximumSize = 200
        ..maximumSizeBytes = 50 << 20; // 50MB
      AppLogger.info('ImageCache configurado: max 200 imagens / 50MB', tag: 'INIT');
      
      // 0. ⚠️ NÃO forçar refresh de token no Splash.
      // Isso pode travar por rede e não é crítico para a Home abrir.
      // Se precisar, fazemos best-effort no warmup pós-primeiro-frame.

      final currentUserId = AppState.currentUserId;
      
      // 1. Pré-carrega avatar do usuário (HomeAppBar)
      if (currentUserId != null && currentUserId.isNotEmpty) {
        AppLogger.info('Pré-carregando avatar do usuário (HomeAppBar)...', tag: 'INIT');
        try {
          final userRepo = UserRepository();
          final currentUserData = await userRepo
              .getUserById(currentUserId)
              .timeout(const Duration(seconds: 3));
          if (currentUserData != null) {
            // ✅ Seed da localização inicial do mapa via Firestore.
            // Evita o primeiro frame em São Paulo quando o user já tem coords persistidas.
            // 🔒 Usa displayLatitude/displayLongitude (com offset) com fallback para latitude/longitude
            try {
              // Prioriza displayLatitude/displayLongitude (dados públicos com offset)
              final rawLat = currentUserData['displayLatitude'] ?? currentUserData['latitude'];
              final rawLng = currentUserData['displayLongitude'] ?? currentUserData['longitude'];

              final lat = rawLat is num ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
              final lng = rawLng is num ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');

              if (lat != null && lng != null) {
                mapViewModel.seedInitialLocation(LatLng(lat, lng));
                AppLogger.success('Seed de localização inicial aplicado (Firestore)', tag: 'INIT');
              }
            } catch (e) {
              AppLogger.warning('Seed de localização inicial falhou: $e', tag: 'INIT');
            }

            // ✅ Preload do nome no UserStore para evitar "pop" no HomeAppBar
            final rawName = currentUserData['fullName'] ??
                currentUserData['full_name'] ??
                currentUserData['name'];
            final fullName = rawName is String ? rawName : rawName?.toString();
            if (fullName != null && fullName.trim().isNotEmpty) {
              UserStore.instance.preloadName(currentUserId, fullName);
            }

            // Avatar será carregado pelo StableAvatar usando o photoUrl
            AppLogger.success('Avatar do usuário pré-carregado', tag: 'INIT');
            AppLogger.info('Nome: ${currentUserData['full_name'] ?? 'N/A'}', tag: 'INIT');
            AppLogger.info(
              'Localização: ${currentUserData['locality'] ?? 'N/A'}, ${currentUserData['state'] ?? 'N/A'}',
              tag: 'INIT',
            );
          }
        } catch (e) {
          AppLogger.warning('Erro ao pré-carregar avatar: $e', tag: 'INIT');
        }
      }
      
      // 2. ✅ PRÉ-CARREGAR EVENTOS DO MAPA (evita flash do filtro de categorias)
      // Isso garante que eventsInBoundsCount > 0 antes do DiscoverTab montar
      AppLogger.info('Pré-carregando eventos do mapa...', tag: 'INIT');
      try {
        if (!mapViewModel.mapReady && !mapViewModel.isLoading) {
          await mapViewModel.initialize().timeout(const Duration(seconds: 8));
        }
      } on TimeoutException {
        AppLogger.warning(
          'Timeout ao pré-carregar eventos do mapa (critical). Continuando.',
          tag: 'INIT',
        );
      } catch (e) {
        AppLogger.warning('Erro ao pré-carregar eventos do mapa: $e', tag: 'INIT');
      }
      
      AppLogger.success('Bootstrap crítico completo!', tag: 'INIT');
      AppLogger.info('Eventos carregados: ${mapViewModel.events.length}', tag: 'INIT');
      AppLogger.info('Markers gerados (cache): ${mapViewModel.googleMarkers.length}', tag: 'INIT');
      AppLogger.info('Mapa pronto: ${mapViewModel.mapReady}', tag: 'INIT');
      AppLogger.info('Markers serão regenerados com callbacks no GoogleMapView', tag: 'INIT');
      
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro durante inicialização crítica (não bloqueia abertura)',
        tag: 'INIT',
        error: e,
        stackTrace: stackTrace,
      );
      // Não lançar erro - deixar app abrir mesmo com falha
      // O ViewModel tentará carregar novamente quando o mapa estiver pronto
    }
  }

  /// Warmup pesado para rodar DEPOIS do primeiro frame (Home)
  ///
  /// - Pré-carrega pins + eventos + markers (mapViewModel.initialize)
  /// - Pré-carrega conversas (cache/firestore)
  /// - Participantes do GroupInfo: on-demand (quando abrir a tela)
  Future<void> warmupAfterFirstFrame() async {
    try {
      AppLogger.info('Warmup pós-primeiro-frame iniciado...', tag: 'INIT');

      // 0) Token refresh (best-effort, não bloqueia)
      // Mantém a sessão saudável, mas não deve segurar a Home.
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) {
        Future(() async {
          try {
            await auth.currentUser!
                .getIdToken(true)
                .timeout(const Duration(seconds: 2));
            AppLogger.success('Token de autenticação renovado (warmup)', tag: 'INIT');
          } catch (e) {
            AppLogger.warning('Warmup token refresh falhou: $e', tag: 'INIT');
          }
        });
      }

      // 0.5) BlockService (reativo) — mover do Splash para o warmup
      // Isso cria listeners do Firestore e pode ter custo variável; no Splash não vale.
      final currentUserId = AppState.currentUserId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        try {
          await BlockService()
              .initialize(currentUserId)
              .timeout(const Duration(seconds: 2));
          AppLogger.success('BlockService inicializado (warmup)', tag: 'INIT');
        } catch (e) {
          AppLogger.warning('Warmup BlockService falhou: $e', tag: 'INIT');
        }
      }

      // 1) MapViewModel (maior custo) — deixa mapa ir carregando em background
      if (!mapViewModel.mapReady && !mapViewModel.isLoading) {
        await mapViewModel.initialize();
      } else {
        AppLogger.info('Warmup mapa ignorado (já pronto/carregando)', tag: 'INIT');
      }

      // 1.05) Se o mapa está inicializando em paralelo (ex.: DiscoverScreen),
      // espera um snapshot mínimo (location + events) para conseguir fazer warmup.
      // Não bloqueia: timeout curto.
      final snapshot = await _waitForInitialMapSnapshot();

      // 1.1) Warmup de avatares do viewport inicial (best-effort)
      //
      // Objetivo: quando o GoogleMapView for gerado após o Splash, os markers já
      // nasçam com o bitmap do avatar em cache (sem passar por empty state).
      //
      // Limitação: no AppInitializer não temos acesso ao GoogleMapController,
      // então aproximamos o bounding box inicial por um raio em km ao redor da
      // localização inicial (zoom padrão ~12).
      try {
        final location = snapshot?.location ?? mapViewModel.lastLocation;
        final events = snapshot?.events ?? mapViewModel.events;

        if (location != null && events.isNotEmpty) {
          const initialViewportWarmupRadiusKm = 25.0;
          const maxUsersToWarm = 30;

          // Helper local para bounding box (graus) a partir de raio em km.
          // Mesmo princípio do GeoService, mas sem depender dele aqui.
          const earthRadiusKm = 6371.0;
          final lat = location.latitude;
          final lng = location.longitude;
          final latDelta = initialViewportWarmupRadiusKm / earthRadiusKm * (180 / 3.141592653589793);
          final lngDelta = initialViewportWarmupRadiusKm /
              (earthRadiusKm * (cos(lat * 3.141592653589793 / 180))) *
              (180 / 3.141592653589793);

          final minLat = lat - latDelta;
          final maxLat = lat + latDelta;
          final minLng = lng - lngDelta;
          final maxLng = lng + lngDelta;

          final viewportEvents = events.where((e) {
            final withinLat = e.lat >= minLat && e.lat <= maxLat;
            final withinLng = e.lng >= minLng && e.lng <= maxLng;
            return withinLat && withinLng;
          }).toList(growable: false);

          if (viewportEvents.isNotEmpty) {
            final markerService = GoogleEventMarkerService();
            // Timeout mais generoso (5s) para primeira impressão do usuário.
            // Melhor demorar um pouco mais no splash do que mostrar empty state.
            final loaded = await markerService
                .preloadAvatarPinsForEvents(viewportEvents, maxUsers: maxUsersToWarm)
                .timeout(const Duration(seconds: 5));

            AppLogger.success(
              'Warmup avatares viewport OK (loaded=$loaded, events=${viewportEvents.length}, maxUsers=$maxUsersToWarm)',
              tag: 'INIT',
            );
          }
        }
      } catch (e) {
        AppLogger.warning('Warmup avatares viewport falhou: $e', tag: 'INIT');
      }

      // 1.2) Warmup da descoberta de pessoas (PeopleButton / FindPeople)
      // Objetivo: pré-carregar count e o primeiro avatar do modo "Perto de você"
      // antes do usuário interagir com o mapa.
      try {
        final location = snapshot?.location ?? mapViewModel.lastLocation;
        if (location != null) {
          const initialPeopleWarmupRadiusKm = 25.0;

          const earthRadiusKm = 6371.0;
          final lat = location.latitude;
          final lng = location.longitude;
          final latDelta = initialPeopleWarmupRadiusKm / earthRadiusKm * (180 / 3.141592653589793);
          final lngDelta = initialPeopleWarmupRadiusKm /
              (earthRadiusKm * (cos(lat * 3.141592653589793 / 180))) *
              (180 / 3.141592653589793);

          final bounds = MapBounds(
            minLat: lat - latDelta,
            maxLat: lat + latDelta,
            minLng: lng - lngDelta,
            maxLng: lng + lngDelta,
          );

          final peopleService = PeopleMapDiscoveryService();
          // ⚠️ Importante: aqui é warmup, então NÃO publicamos no `nearbyPeople`.
          // Se publicarmos, o PeopleButton pode mostrar um resultado de raio
          // aproximado antes do mapa calcular o viewport real.
          await peopleService.preloadForBounds(bounds).timeout(const Duration(seconds: 5));

          AppLogger.success(
            'Warmup pessoas viewport OK (bounds≈${initialPeopleWarmupRadiusKm.toStringAsFixed(0)}km)',
            tag: 'INIT',
          );
        }
      } catch (e) {
        AppLogger.warning('Warmup pessoas viewport falhou: $e', tag: 'INIT');
      }

      // 2) Conversas — pode ficar para quando entrar na aba, mas aqui é warmup
      try {
        await conversationsViewModel.preloadConversations();
      } catch (e) {
        AppLogger.warning('Warmup conversas falhou: $e', tag: 'INIT');
      }

      AppLogger.success('Warmup pós-primeiro-frame concluído', tag: 'INIT');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Erro no warmup pós-primeiro-frame',
        tag: 'INIT',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
