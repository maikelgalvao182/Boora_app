part of '../map_viewmodel.dart';
extension MapViewModelMarkers on MapViewModel {
  /// Gera markers do Google Maps
  /// 
  /// NOTA: Os markers gerados aqui podem não ter callbacks corretos
  /// porque onMarkerTap é configurado pelo GoogleMapView.initState()
  /// Os BITMAPS pré-carregados são o que importa para performance
  Future<void> _generateGoogleMarkers() async {
    final markers = await _googleMarkerService.buildEventMarkers(
      _events,
      onTap: onMarkerTap != null ? (eventId) {
        debugPrint('🟢 Google Maps marker tapped: $eventId');
        final event = _events.firstWhere((e) => e.id == eventId);
        onMarkerTap!(event);
      } : null,
    );
    _googleMarkers = markers;
  }

  /// Enriquece eventos com distância e disponibilidade ANTES de criar markers
  /// 
  /// ⚠️ **DEPRECATED (PR2):** Este método faz N+1 queries (busca creator, participants,
  /// userApplication para CADA evento). Não deve ser usado no fluxo do mapa.
  /// 
  /// Se precisar de dados enriquecidos (ex: ao abrir EventCard), use um serviço
  /// com cache TTL por eventId.
  /// 
  /// IMPORTANTE: Esta é a ÚNICA fonte de verdade para calcular:
  /// - distanceKm: Distância do evento para o usuário
  /// - isAvailable: Se o usuário pode ver o evento (premium OU dentro de 30km)
  /// - creatorFullName: Usa dados desnormalizados do Firestore (OTIMIZAÇÃO: elimina N+1 queries)
  /// 
  /// Os repositórios (EventMapRepository) NÃO devem incluir esses campos - 
  /// toda lógica de enriquecimento fica aqui no ViewModel
  @Deprecated('Use cache por eventId ao abrir card. Não chamar no fluxo do mapa.')
  Future<void> _enrichEvents() async {
    if (_lastLocation == null || _events.isEmpty) return;

    final currentUserId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Buscar dados do usuário atual para verificar premium E idade
    final currentUserDoc = await _userRepository.getUserById(currentUserId);
    bool isPremium = currentUserDoc?['hasPremium'] as bool? ?? false;
    
    // 👑 VERIFICAR status VIP em users_preview (se não for premium via RevenueCat)
    if (!isPremium) {
      try {
        final userPreviewDoc = await firebase_firestore.FirebaseFirestore.instance
            .collection('users_preview')
            .doc(currentUserId)
            .get();
        
        if (userPreviewDoc.exists) {
          final data = userPreviewDoc.data();
          dynamic rawVip = data?['IsVip'] ?? data?['user_is_vip'] ?? data?['isVip'] ?? data?['vip'];
          
          if (rawVip is bool) {
            isPremium = rawVip;
          } else if (rawVip is String) {
            isPremium = rawVip.toLowerCase() == 'true';
          }
          
          if (isPremium) {
            debugPrint('👑 [MapViewModel] Usuário é VIP (users_preview) - permitindo eventos além de 30km');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [MapViewModel] Erro ao verificar IsVip: $e');
      }
    }
    
    final userAge = currentUserDoc?['age'] as int?;

    // Enriquecer cada evento (agora assíncrono para buscar nomes faltantes)
    final enrichedEvents = await Future.wait(_events.map((event) async {
      // 🚨 VALIDAÇÃO: Verificar se coordenadas são válidas (detectar bug Web Mercator)
      final userLat = _lastLocation!.latitude;
      final userLng = _lastLocation!.longitude;
      final eventLat = event.lat;
      final eventLng = event.lng;
      
      // Validar coordenadas do usuário
      if (userLat < -90 || userLat > 90 || userLng < -180 || userLng > 180) {
        debugPrint('🚨 [MapViewModel] COORDENADAS INVÁLIDAS DO USUÁRIO:');
        debugPrint('   userLat: $userLat, userLng: $userLng');
        debugPrint('   Parece ser Web Mercator em vez de lat/lng em graus!');
      }
      
      // Validar coordenadas do evento
      if (eventLat < -90 || eventLat > 90 || eventLng < -180 || eventLng > 180) {
        debugPrint('🚨 [MapViewModel] COORDENADAS INVÁLIDAS DO EVENTO ${event.id}:');
        debugPrint('   eventLat: $eventLat, eventLng: $eventLng');
        debugPrint('   Parece ser Web Mercator em vez de lat/lng em graus!');
      }
      
      // 1. Calcular distância do evento para o usuário (Haversine - ~2ms por evento)
      final distance = GeoDistanceHelper.distanceInKm(
        userLat,
        userLng,
        eventLat,
        eventLng,
      );

      // 2. Verificar disponibilidade usando regra de negócio
      final isAvailable = _canApplyToEvent(
        isPremium: isPremium,
        distanceKm: distance,
      );
      
      // 🔍 LOG DE DIAGNÓSTICO: Quando evento NÃO está disponível
      if (!isAvailable) {
        debugPrint('🔒 [MapViewModel] Evento "${event.title}" (${event.id}) FORA DA ÁREA:');
        debugPrint('   📍 Usuário: ($userLat, $userLng)');
        debugPrint('   📍 Evento: ($eventLat, $eventLng)');
        debugPrint('   📏 Distância calculada: ${distance.toStringAsFixed(2)} km');
        debugPrint('   👑 isPremium: $isPremium');
        debugPrint('   🎯 Limite FREE: $FREE_ACCOUNT_MAX_EVENT_DISTANCE_KM km');
      }

      // 3. Garantir que creatorFullName esteja presente
      // Se não vier desnormalizado, buscar sob demanda
      String? creatorFullName = event.creatorFullName;
      if (creatorFullName == null && event.createdBy.isNotEmpty) {
        try {
          final userDoc = await _userRepository.getUserBasicInfo(event.createdBy);
          creatorFullName = userDoc?['fullName'];
        } catch (e) {
          debugPrint('⚠️ Erro ao buscar nome do criador para evento ${event.id}: $e');
        }
      }

      // 4. Buscar participantes aprovados (avatares e nomes)
      List<Map<String, dynamic>>? participants;
      try {
        participants = await _applicationRepository.getApprovedApplicationsWithUserData(event.id);
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar participantes para evento ${event.id}: $e');
      }

      // 5. Buscar aplicação do usuário atual (para saber se está aprovado/pendente)
      dynamic userApplication;
      try {
        userApplication = await _applicationRepository.getUserApplication(
          eventId: event.id,
          userId: currentUserId,
        );
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar aplicação do usuário para evento ${event.id}: $e');
      }

      // 6. Validar restrições de idade usando dados que já vieram do EventModel
      bool isAgeRestricted = false;
      
      // Validar idade apenas se não for o criador e houver restrições definidas
      final isCreator = event.createdBy == currentUserId;
      if (!isCreator && event.minAge != null && event.maxAge != null && userAge != null) {
        isAgeRestricted = userAge < event.minAge! || userAge > event.maxAge!;
        
        if (isAgeRestricted) {
          debugPrint('🔒 [MapViewModel] Evento ${event.id} restrito: userAge=$userAge, range=${event.minAge}-${event.maxAge}');
        }
      }

      // 7. Retornar evento enriquecido
      return event.copyWith(
        distanceKm: distance,
        isAvailable: isAvailable,
        creatorFullName: creatorFullName,
        participants: participants,
        userApplication: userApplication,
        isAgeRestricted: isAgeRestricted,
      );
    }));
    
    // Filtrar eventos rejeitados (não mostrar eventos onde o usuário foi rejeitado)
    final eventsBeforeFilter = enrichedEvents.length;
    _events = enrichedEvents.where((event) {
      final isRejected = event.userApplication?.isRejected ?? false;
      if (isRejected) {
        debugPrint('🚫 Evento ${event.id} filtrado (aplicação rejeitada)');
      }
      return !isRejected;
    }).toList();

    final filteredCount = eventsBeforeFilter - _events.length;
    if (filteredCount > 0) {
      debugPrint('🚫 $filteredCount evento(s) rejeitado(s) removido(s) da lista');
    }

    debugPrint('✨ Enriquecidos ${_events.length} eventos com distância e disponibilidade');
  }

  /// Limpa todos os markers
  void clearMarkers() {
    _googleMarkers = {};
    _events = [];
    notifyListeners();
  }

  /// Limpa recursos do ViewModel
  void clear() {
    _googleMarkers = {};
    _events = [];
    notifyListeners();
  }

  /// Limpa cache de markers
  void clearCache() {
    _googleMarkerService.clearCache();
  }
}
