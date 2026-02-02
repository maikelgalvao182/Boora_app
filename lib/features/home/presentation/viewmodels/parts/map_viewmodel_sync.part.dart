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
  /// 
  /// [zoom] - Nível de zoom atual (usado para calcular zoomBucket na chave de cache)
  Future<void> loadEventsInBounds(
    MapBounds bounds, {
    bool prefetchNeighbors = false,
    double? zoom,
  }) async {
    final loadKey = bounds.toQuadkey();
    final inFlight = _inFlightBoundsLoads[loadKey];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = () async {
      debugPrint('🔵 [MapVM] loadEventsInBounds start (events.length=${_events.length})');
      // Estratégia A (stale-while-revalidate): mantém eventos atuais durante o fetch.
      // A UI pode reagir ao loading (spinner), mas não apaga markers por um "vazio" transitório.
      _setLoading(true);
      try {
        // ✅ Cache imediato (sem debounce) para acelerar pan/cold start
        final usedCache = _mapDiscoveryService.tryLoadCachedEventsForBoundsWithPrefetch(
          bounds,
          prefetchNeighbors: prefetchNeighbors,
          zoom: zoom,
        );
        if (usedCache) {
          await _syncEventsFromBounds();
        }

        await _mapDiscoveryService.loadEventsInBounds(
          bounds,
          prefetchNeighbors: prefetchNeighbors,
          zoom: zoom,
        );
        debugPrint('🔵 [MapVM] loadEventsInBounds after service (nearbyEvents.value.length=${_mapDiscoveryService.nearbyEvents.value.length})');
        await _syncEventsFromBounds();
        debugPrint('🔵 [MapVM] loadEventsInBounds after sync (events.length=${_events.length})');
      } finally {
        _setLoading(false);
      }
    }();

    _inFlightBoundsLoads[loadKey] = future;
    try {
      await future;
    } finally {
      if (_inFlightBoundsLoads[loadKey] == future) {
        _inFlightBoundsLoads.remove(loadKey);
      }
    }
  }

  /// Lookahead de cache durante pan (soft apply)
  ///
  /// Usa cache sem debounce e só atualiza se tiver novos eventos.
  Future<bool> softLookaheadForBounds(MapBounds bounds, {double? zoom}) async {
    final applied = _mapDiscoveryService.applyCachedEventsIfNew(bounds, zoom: zoom);
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
        final boundsKey = _buildVisibleBoundsKey();
        final now = DateTime.now();
        final withinWindow = _lastEmptyAt != null &&
            now.difference(_lastEmptyAt!) <= _strongEmptyWindow;

        if (boundsKey != null && boundsKey == _lastEmptyBoundsKey && withinWindow) {
          _consecutiveEmptyForBounds++;
        } else {
          _lastEmptyBoundsKey = boundsKey;
          _consecutiveEmptyForBounds = 1;
        }
        _lastEmptyAt = now;

        final strongEmpty = forceEmpty || _consecutiveEmptyForBounds >= 2;

        if (strongEmpty && _events.isNotEmpty) {
          final requestSeq = _mapDiscoveryService.lastAppliedRequestSeq;
          debugPrint(
            '🟣 [MapVM] clear markers (reason=empty_confirmed, requestSeq=$requestSeq, boundsKey=$boundsKey, eventsCount=${boundsEvents.length})',
          );
          debugPrint('🟣 [MapVM] clearing _events (was ${_events.length})');
          _events = const [];
          eventsVersion.value = (eventsVersion.value + 1).clamp(0, 1 << 30);
          notifyListeners();
        } else if (_events.isNotEmpty) {
          final requestSeq = _mapDiscoveryService.lastAppliedRequestSeq;
          debugPrint(
            '🟣 [MapVM] empty ignored (anti-vazio, requestSeq=$requestSeq, boundsKey=$boundsKey, eventsCount=${boundsEvents.length}, count=$_consecutiveEmptyForBounds)',
          );
        }
      }
      return;
    }

    _lastEmptyBoundsKey = null;
    _lastEmptyAt = null;
    _consecutiveEmptyForBounds = 0;

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
          final cachedCreatorName = _getCachedCreatorName(e.createdBy);
          final creatorFullName = data['creatorFullName'] as String? ?? cachedCreatorName;
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
    
    // ✅ ENRIQUECIMENTO: buscar creatorFullName em background (idempotente)
    unawaited(_enrichCreatorNamesInBackground(mapped));

    // Merge incremental: não substitui _events pelo resultado do bounds.
    // Isso mantém um cache agregado e evita “apagões” ao voltar para áreas já vistas.
    final mappedIds = mapped.map((e) => e.id).toSet();
    final merged = <EventModel>[...mapped];
    for (final prev in _events) {
      if (!mappedIds.contains(prev.id)) {
        merged.add(prev);
      }
    }

    // Mantém o mesmo objeto se nada mudou (reduz rebuilds), mas sem criar
    // "zonas mortas" onde a UI fica visualmente errada e nunca é corrigida.
    final sameLength = merged.length == _events.length;
    final sameIds = sameLength && _events.asMap().entries.every((entry) {
      final i = entry.key;
      return entry.value.id == merged[i].id;
    });

  // Assinatura do snapshot (inclui contexto do viewport), para permitir notify
    // quando o "mesmo dataset" precisa re-renderizar (ex.: bounds mudou,
    // counts mudaram, zoom bucket mudou, ou uma corrida aplicou estado visual inválido).
    final countsSignature = _eventsInBoundsCountByCategory.entries
        .map((e) => '${e.key}:${e.value}')
        .toList(growable: false)
      ..sort();
    // 🔑 zoomBucket na assinatura: força rebuild quando zoom muda de faixa,
    // mesmo que _events seja idêntico. Isso corrige o "preciso mexer de novo".
    final zoomBucket = _currentZoom <= 8 ? 0 : _currentZoom <= 11 ? 1 : _currentZoom <= 14 ? 2 : 3;
  final nextSignature = '${merged.length}|v$_boundsSnapshotVersion|z$zoomBucket|${countsSignature.join(',')}';

    if (sameIds && nextSignature == _eventsSignature) {
      debugPrint('🟣 [MapVM] early-return: sameIds && sameSignature (events.length=${_events.length})');
      return;
    }

    // [FIX] Preservar evento pinado se ele estiver faltando no novo 'merged'
    // Durante navegação via push, o evento injetado pode não vir do bound query imediatamente,
    // então precisamos reinjetá-lo se ele foi pinado recentemente.
    List<EventModel> finalEvents = merged;
    if (_pinnedEventId != null && _isPinned(_pinnedEventId!)) {
      final isPinnedInList = finalEvents.any((e) => e.id == _pinnedEventId);
      if (!isPinnedInList) {
        // Tentar encontrar o evento "velho" na lista atual para preservar
        try {
          final pinnedEvent = _events.firstWhere((e) => e.id == _pinnedEventId);
          debugPrint('📌 [MapVM] Preservando evento pinado $_pinnedEventId durante sync (não veio do bounds)');
          finalEvents = List.from(finalEvents)..add(pinnedEvent);
        } catch (_) {
          // Se não estava na lista antiga também, não há como salvar.
        }
      }
    }

    // ⚖️ Estabilização: se o novo snapshot ficou muito menor, preserva eventos
    // visíveis do snapshot anterior para evitar “apagões” temporários.
    final visibleBounds = _visibleBounds;
    if (visibleBounds != null && finalEvents.length < _events.length) {
      bool contains(double lat, double lng) {
        final sw = visibleBounds.southwest;
        final ne = visibleBounds.northeast;

        final minLat = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
        final maxLat = sw.latitude < ne.latitude ? ne.latitude : sw.latitude;
        final withinLat = lat >= minLat && lat <= maxLat;

        final swLng = sw.longitude;
        final neLng = ne.longitude;
        final withinLng = swLng <= neLng
            ? (lng >= swLng && lng <= neLng)
            : (lng >= swLng || lng <= neLng);

        return withinLat && withinLng;
      }

      final mergedById = <String, EventModel>{
        for (final e in finalEvents) e.id: e,
      };

      for (final prev in _events) {
        if (mergedById.containsKey(prev.id)) continue;
        if (contains(prev.lat, prev.lng)) {
          mergedById[prev.id] = prev;
        }
      }

      final merged = mergedById.values.toList(growable: false);
      if (merged.length > finalEvents.length) {
        finalEvents = merged;
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
