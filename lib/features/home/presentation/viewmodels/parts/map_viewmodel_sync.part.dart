part of '../map_viewmodel.dart';
extension MapViewModelSync on MapViewModel {
  /// Inicializa o ViewModel
  /// 
  /// Deve ser chamado após o mapa estar pronto
  /// 
  /// Este método:
  /// 1. Pré-carrega pins padrão
  /// 2. Carrega eventos próximos (popula cache de bitmaps durante geração de markers)
  /// 
  /// NOTA: O cache de bitmaps é SINGLETON (GoogleEventMarkerService)
  /// então os bitmaps gerados aqui serão reutilizados pelo GoogleMapView.
  Future<void> initialize() async {
    if (_didInitialize) {
      return;
    }

    _didInitialize = true;

    try {
      // Pré-carregar pins (imagens) para Google Maps
      await _googleMarkerService.preloadDefaultPins();

      // Carregar eventos iniciais apenas se ainda não temos nada em memória.
      // Evita competir com o stream de eventos em tempo real.
      final hasEvents = _events.isNotEmpty;
      if (!hasEvents && !_mapReady) {
        await loadNearbyEvents();
      }
    } catch (e, stack) {
      AppLogger.error(
        'Falha ao inicializar MapViewModel',
        tag: 'MAP',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Carrega eventos próximos à localização do usuário
  /// 
  /// **REFATORADO (PR2):** Agora delega para o fluxo bounds-based, que é
  /// otimizado com cache TTL e debounce. Não faz mais N+1 queries.
  /// 
  /// Este método:
  /// 1. Obtém localização do usuário
  /// 2. Cria bounds de ~10km ao redor da localização
  /// 3. Delega para loadEventsInBounds() (cache + debounce + sem N+1)
  Future<void> loadNearbyEvents() async {
    if (_isLoading) return;

    _setLoading(true);

    try {
      // 1. Obter localização
      final locationResult = await _locationService.getUserLocation();
      _lastLocation = locationResult.location;

      if (_lastLocation == null) {
        AppLogger.warning('Localização não disponível', tag: 'MAP');
        return;
      }

      // 2. Criar bounds de ~10km ao redor da localização
      // (~0.09 graus ≈ 10km de raio)
      const radiusDegrees = 0.09;
      final bounds = MapBounds(
        minLat: _lastLocation!.latitude - radiusDegrees,
        maxLat: _lastLocation!.latitude + radiusDegrees,
        minLng: _lastLocation!.longitude - radiusDegrees,
        maxLng: _lastLocation!.longitude + radiusDegrees,
      );

      // 3. Delegar para fluxo bounds-based (cache TTL + debounce)
      await loadEventsInBounds(bounds);
      
      AppLogger.info('Eventos carregados via bounds: ${_events.length}', tag: 'MAP');
      
      // SOMENTE AQUI o mapa está realmente pronto
      _setMapReady(true);
      
    } catch (e) {
      AppLogger.error('Erro ao carregar eventos do mapa', tag: 'MAP', error: e);
      // Erro será silencioso - markers continuam vazios
      _googleMarkers = {};
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Atualiza eventos para uma localização específica
  /// 
  /// Útil quando o usuário move o mapa manualmente
  /// 
  /// **REFATORADO (PR2):** Agora delega para o fluxo bounds-based.
  Future<void> loadEventsAt(LatLng location) async {
    if (_isLoading) return;

    _setLoading(true);
    _lastLocation = location;

    try {
      // Criar bounds de ~10km ao redor da localização
      const radiusDegrees = 0.09;
      final bounds = MapBounds(
        minLat: location.latitude - radiusDegrees,
        maxLat: location.latitude + radiusDegrees,
        minLng: location.longitude - radiusDegrees,
        maxLng: location.longitude + radiusDegrees,
      );

      // Delegar para fluxo bounds-based (cache TTL + debounce)
      await loadEventsInBounds(bounds);

      notifyListeners();
    } catch (e) {
      debugPrint('❌ MapViewModel: Erro ao carregar eventos: $e');
      _googleMarkers = {};
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Recarrega eventos (força atualização)
  Future<void> refresh() async {
    if (_lastLocation != null) {
      await loadEventsAt(_lastLocation!);
    } else {
      await loadNearbyEvents();
    }
  }

  /// Atualiza categorias do drawer baseado no bounding box visível
  /// 
  /// Chamado pelo GoogleMapView quando a câmera para de mover.
  /// Isso mantém os chips de categoria sincronizados com o viewport.
  Future<void> loadEventsInBounds(
    MapBounds bounds, {
    bool prefetchNeighbors = false,
  }) async {
    debugPrint('🔵 [MapVM] loadEventsInBounds start (events.length=${_events.length})');
    // Estratégia A (stale-while-revalidate): mantém eventos atuais durante o fetch.
    // A UI pode reagir ao loading (spinner), mas não apaga markers por um "vazio" transitório.
    _setLoading(true);
    try {
      // ✅ Cache imediato (sem debounce) para acelerar pan/cold start
      final usedCache = _mapDiscoveryService.tryLoadCachedEventsForBoundsWithPrefetch(
        bounds,
        prefetchNeighbors: prefetchNeighbors,
      );
      if (usedCache) {
        await _syncEventsFromBounds();
      }

      await _mapDiscoveryService.loadEventsInBounds(
        bounds,
        prefetchNeighbors: prefetchNeighbors,
      );
      debugPrint('🔵 [MapVM] loadEventsInBounds after service (nearbyEvents.value.length=${_mapDiscoveryService.nearbyEvents.value.length})');
      await _syncEventsFromBounds();
      debugPrint('🔵 [MapVM] loadEventsInBounds after sync (events.length=${_events.length})');
    } finally {
      _setLoading(false);
    }
  }

  /// Lookahead de cache durante pan (soft apply)
  ///
  /// Usa cache sem debounce e só atualiza se tiver novos eventos.
  Future<bool> softLookaheadForBounds(MapBounds bounds) async {
    final applied = _mapDiscoveryService.applyCachedEventsIfNew(bounds);
    if (!applied) return false;

    await _syncEventsFromBounds();
    return true;
  }

  /// Força refresh imediato das categorias do drawer
  /// 
  /// Ignora cache e debounce. Usado na inicialização do mapa.
  Future<void> forceRefreshBounds(MapBounds bounds) async {
    // Refresh forçado: aqui o resultado (inclusive vazio) é considerado "confirmado".
    _setLoading(true);
    try {
      await _mapDiscoveryService.forceRefresh(bounds);
      await _syncEventsFromBounds(forceEmpty: true);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _syncEventsFromBounds({bool forceEmpty = false}) async {
    debugPrint('🟣 [MapVM] _syncEventsFromBounds start (forceEmpty=$forceEmpty)');
    // Mesmo que a lista final não mude, houve uma tentativa de sync do viewport.
    // Atualizamos a versão para permitir notificar a UI quando necessário.
    _boundsSnapshotVersion = (_boundsSnapshotVersion + 1).clamp(0, 1 << 30);
    final boundsEvents = _mapDiscoveryService.nearbyEvents.value;
    debugPrint('🟣 [MapVM] boundsEvents.length=${boundsEvents.length} isLoading=${_mapDiscoveryService.isLoading}');
    if (boundsEvents.isEmpty) {
      // "Vazio" pode ser transitório por debounce / in-flight request.
      // Estratégia A: manter dados atuais enquanto o MapDiscovery ainda está carregando.
      final emptyConfirmed = forceEmpty || !_mapDiscoveryService.isLoading;
      debugPrint('🟣 [MapVM] boundsEvents.isEmpty => emptyConfirmed=$emptyConfirmed');

      if (emptyConfirmed) {
        if (_events.isNotEmpty) {
          debugPrint('🟣 [MapVM] clearing _events (was ${_events.length})');
          _events = const [];
          eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
          notifyListeners();
        }
      }
      return;
    }

    // Obter dados do usuário para calcular distância e verificar premium
    final currentUserId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    bool isPremium = false;
    
    if (currentUserId != null) {
      try {
        final userDoc = await _userRepository.getUserById(currentUserId);
        isPremium = userDoc?['hasPremium'] as bool? ?? false;
      } catch (_) {}
    }

    // Converte EventLocation -> EventModel
    // ✅ Agora extrai TODOS os campos necessários do eventData
    final mapped = boundsEvents
        .map((e) {
          final data = e.eventData;
          final location = data['location'] as Map<String, dynamic>?;
          final participantsData = data['participants'] as Map<String, dynamic>?;
          final scheduleData = data['schedule'] as Map<String, dynamic>?;
          
          // Parse schedule date
          DateTime? scheduleDate;
          final dateField = scheduleData?['date'];
          if (dateField != null) {
            try {
              scheduleDate = dateField.toDate();
            } catch (_) {}
          }
          
          // Parse photoReferences
          List<String>? photoReferences;
          final photoRefs = location?['photoReferences'] as List<dynamic>?;
          if (photoRefs != null) {
            photoReferences = photoRefs.map((ref) => ref.toString()).toList();
          }
          
          // ✅ Calcular distância e disponibilidade
          double? distanceKm;
          bool isAvailable = true;
          
          if (_lastLocation != null) {
            distanceKm = GeoDistanceHelper.distanceInKm(
              _lastLocation!.latitude,
              _lastLocation!.longitude,
              e.latitude,
              e.longitude,
            );
            
            // Regra de negócio: Premium pode aplicar em qualquer evento,
            // Free só pode aplicar em eventos dentro de 30km
            isAvailable = isPremium || distanceKm <= FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM;
          }
          
          // ✅ Extrair creatorFullName do eventData se disponível (desnormalizado)
          final creatorFullName = data['creatorFullName'] as String?;
          // ✅ Extrair avatar desnormalizado (N+1 killer)
          final creatorAvatarUrl = data['organizerAvatarThumbUrl'] as String? ?? 
                                   data['creatorPhotoUrl'] as String? ??
                                   data['authorPhotoUrl'] as String?;
          
          return EventModel(
            id: e.eventId,
            emoji: e.emoji,
            createdBy: e.createdBy,
            lat: e.latitude,
            lng: e.longitude,
            title: data['activityText'] as String? ?? e.title,
            category: e.category?.trim(),
            // ✅ Campos essenciais que estavam faltando:
            locationName: location?['locationName'] as String?,
            formattedAddress: location?['formattedAddress'] as String?,
            placeId: location?['placeId'] as String?,
            photoReferences: photoReferences,
            scheduleDate: scheduleDate,
            privacyType: participantsData?['privacyType'] as String? ?? 'open',
            minAge: participantsData?['minAge'] as int?,
            maxAge: participantsData?['maxAge'] as int?,
            // ✅ Campos de distância e disponibilidade
            distanceKm: distanceKm,
            isAvailable: isAvailable,
            creatorFullName: creatorFullName,
            creatorAvatarUrl: creatorAvatarUrl,
          );
        })
        .toList(); // ✅ Lista MUTÁVEL para permitir enriquecimento
    
    // ✅ ENRIQUECIMENTO: Buscar creatorFullName para eventos que não têm
    // Faz em paralelo para não bloquear a UI
    final eventsNeedingCreatorName = mapped.where((e) => e.creatorFullName == null).toList();
    if (eventsNeedingCreatorName.isNotEmpty) {
      // Coletar IDs únicos de criadores
      final creatorIds = eventsNeedingCreatorName.map((e) => e.createdBy).toSet().toList();
      
      debugPrint('🔄 [MapVM] Buscando nomes de ${creatorIds.length} criadores...');
      
      // Buscar nomes em batch (usar cache do UserRepository)
      try {
        final usersData = await _userRepository.getUsersBasicInfo(creatorIds);
        final creatorNames = <String, String>{};
        for (final userData in usersData) {
          final id = userData['userId'] as String?;
          final name = userData['fullName'] as String?;
          if (id != null && name != null) {
            creatorNames[id] = name;
          }
        }
        
        // Atualizar os eventos com os nomes (lista mutável)
        for (var i = 0; i < mapped.length; i++) {
          final event = mapped[i];
          if (event.creatorFullName == null && creatorNames.containsKey(event.createdBy)) {
            mapped[i] = event.copyWith(creatorFullName: creatorNames[event.createdBy]);
          }
        }
        
        debugPrint('✅ [MapVM] Enriqueceu ${creatorNames.length} criadores para ${eventsNeedingCreatorName.length} eventos');
      } catch (e) {
        debugPrint('⚠️ [MapVM] Erro ao buscar nomes de criadores: $e');
        // Continua sem os nomes - o EventCardController vai buscar sob demanda
      }
    }

    // Mantém o mesmo objeto se nada mudou (reduz rebuilds), mas sem criar
    // "zonas mortas" onde a UI fica visualmente errada e nunca é corrigida.
    final sameLength = mapped.length == _events.length;
    final sameIds = sameLength && _events.asMap().entries.every((entry) {
      final i = entry.key;
      return entry.value.id == mapped[i].id;
    });

  // Assinatura do snapshot (inclui contexto do viewport), para permitir notify
    // quando o "mesmo dataset" precisa re-renderizar (ex.: bounds mudou,
    // counts mudaram, ou uma corrida aplicou estado visual inválido).
    final countsSignature = _eventsInBoundsCountByCategory.entries
        .map((e) => '${e.key}:${e.value}')
        .toList(growable: false)
      ..sort();
  final nextSignature = '${mapped.length}|v$_boundsSnapshotVersion|${countsSignature.join(',')}';

    if (sameIds && nextSignature == _eventsSignature) {
      debugPrint('🟣 [MapVM] early-return: sameIds && sameSignature (events.length=${_events.length})');
      return;
    }

    // [FIX] Preservar evento pinado se ele estiver faltando no novo 'mapped'
    // Durante navegação via push, o evento injetado pode não vir do bound query imediatamente,
    // então precisamos reinjetá-lo se ele foi pinado recentemente.
    List<EventModel> finalEvents = mapped;
    if (_pinnedEventId != null && _isPinned(_pinnedEventId!)) {
      final isPinnedInList = mapped.any((e) => e.id == _pinnedEventId);
      if (!isPinnedInList) {
        // Tentar encontrar o evento "velho" na lista atual para preservar
        try {
          final pinnedEvent = _events.firstWhere((e) => e.id == _pinnedEventId);
          debugPrint('📌 [MapVM] Preservando evento pinado $_pinnedEventId durante sync (não veio do bounds)');
          finalEvents = List.from(mapped)..add(pinnedEvent);
        } catch (_) {
          // Se não estava na lista antiga também, não há como salvar.
        }
      }
    }

    debugPrint('🟣 [MapVM] updating _events: ${_events.length} -> ${finalEvents.length} (signature=$nextSignature)');
    _events = finalEvents;
    _eventsSignature = nextSignature;
    eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
    notifyListeners();
  }

  /// Verifica se o usuário pode aplicar para um evento
  /// 
  /// Regra de negócio:
  /// - Usuários premium podem ver todos os eventos (ilimitado)
  /// - Usuários free podem ver apenas eventos dentro do limite configurado
  bool _canApplyToEvent({
    required bool isPremium,
    required double distanceKm,
  }) {
    return isPremium || distanceKm <= FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM;
  }
}
