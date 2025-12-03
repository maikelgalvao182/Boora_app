import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/services/location/geo_utils.dart';
import 'package:partiu/services/location/distance_isolate.dart';
import 'package:partiu/services/location/location_stream_controller.dart';

/// Serviço principal para queries de localização com filtro de raio
/// 
/// Responsabilidades:
/// - Carregar eventos dentro do raio do usuário
/// - Cache com TTL (30 segundos)
/// - Bounding box para queries otimizadas
/// - Isolate para cálculo de distâncias sem jank
/// - Stream de atualizações automáticas
class LocationQueryService {
  /// Singleton
  static final LocationQueryService _instance =
      LocationQueryService._internal();
  factory LocationQueryService() => _instance;
  LocationQueryService._internal() {
    _initializeListeners();
  }

  /// Cache de localização do usuário
  UserLocationCache? _userLocationCache;

  /// Cache de eventos
  EventsCache? _eventsCache;

  /// Filtros atuais
  EventFilterOptions _currentFilters = EventFilterOptions();

  /// Stream controller para eventos
  final _eventsStreamController =
      StreamController<List<EventWithDistance>>.broadcast();

  /// TTL do cache (30 segundos)
  static const Duration cacheTTL = Duration(seconds: 30);

  /// Stream de eventos
  Stream<List<EventWithDistance>> get eventsStream =>
      _eventsStreamController.stream;

  /// Inicializa listeners para mudanças de raio/localização
  void _initializeListeners() {
    final streamController = LocationStreamController();

    // Listener de mudanças de raio
    streamController.radiusStream.listen((radiusKm) {
      debugPrint('🔄 LocationQueryService: Raio mudou para $radiusKm km');
      _invalidateEventsCache();
      _loadAndEmitEvents();
    });

    // Listener de reload manual
    streamController.reloadStream.listen((_) {
      debugPrint('🔄 LocationQueryService: Reload manual solicitado');
      _invalidateAllCaches();
      _loadAndEmitEvents();
    });
  }

  /// Atualiza os filtros e recarrega eventos
  void updateFilters(EventFilterOptions filters) {
    _currentFilters = filters;
    debugPrint('🔄 LocationQueryService: Filtros atualizados');
    _invalidateEventsCache();
    _loadAndEmitEvents();
  }

  /// Busca eventos dentro do raio - versão única (sem stream)
  /// 
  /// Uso: Quando precisa de uma consulta pontual
  Future<List<EventWithDistance>> getEventsWithinRadiusOnce({
    double? customRadiusKm,
    EventFilterOptions? filters,
  }) async {
    try {
      final activeFilters = filters ?? _currentFilters;

      // 1. Carregar localização do usuário
      final userLocation = await _getUserLocation();

      // 2. Obter raio
      final radiusKm = customRadiusKm ?? await _getUserRadius();

      // 3. Verificar cache de eventos (apenas se filtros não mudaram)
      // Nota: Para cache perfeito com filtros, precisaríamos incluir filtros na chave do cache
      // Por simplicidade, invalidamos cache ao mudar filtros
      if (_eventsCache != null &&
          !_eventsCache!.isExpired &&
          _eventsCache!.radiusKm == radiusKm) {
        debugPrint('✅ LocationQueryService: Usando cache de eventos');
        return _eventsCache!.events;
      }

      // 4. Calcular bounding box
      final boundingBox = GeoUtils.calculateBoundingBox(
        centerLat: userLocation.latitude,
        centerLng: userLocation.longitude,
        radiusKm: radiusKm,
      );

      // 5. Query Firestore (primeira filtragem rápida - Bounding Box)
      final candidateEvents = await _filterByBoundingBox(boundingBox);

      // 6. Buscar criadores e unificar dados (Orquestração)
      final unifiedEvents = await _enrichEventsWithCreators(candidateEvents);

      // 7. Filtros em memória (Gender, Age, Verified, Interests) - Agora baseados no CRIADOR
      var filteredEvents = _filterByGender(unifiedEvents, activeFilters.gender);
      filteredEvents = _filterByAge(filteredEvents, activeFilters.minAge, activeFilters.maxAge);
      filteredEvents = _filterByVerified(filteredEvents, activeFilters.isVerified);
      filteredEvents = _filterByInterests(filteredEvents, activeFilters.interests);

      // 8. Filtrar com isolate (distância exata e cálculos pesados)
      final finalEvents = await _filterByDistanceIsolate(
        events: filteredEvents,
        centerLat: userLocation.latitude,
        centerLng: userLocation.longitude,
        radiusKm: radiusKm,
      );

      // 9. Atualizar cache
      _eventsCache = EventsCache(
        events: finalEvents,
        radiusKm: radiusKm,
        timestamp: DateTime.now(),
      );

      debugPrint(
          '✅ LocationQueryService: ${finalEvents.length} eventos retornados após todos os filtros (Orquestrado)');

      return finalEvents;
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao buscar eventos: $e');
      return [];
    }
  }

  /// Busca eventos dentro do raio - versão stream (atualização automática)
  /// 
  /// Uso: Quando precisa de atualizações em tempo real
  Stream<List<EventWithDistance>> getEventsWithinRadiusStream({
    double? customRadiusKm,
  }) async* {
    while (true) {
      final events = await getEventsWithinRadiusOnce(
        customRadiusKm: customRadiusKm,
      );
      yield events;

      // Aguardar próxima atualização
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  /// Carrega eventos e emite no stream principal
  Future<void> _loadAndEmitEvents() async {
    final events = await getEventsWithinRadiusOnce();
    if (!_eventsStreamController.isClosed) {
      _eventsStreamController.add(events);
    }
  }

  /// Busca localização do usuário (com cache)
  Future<UserLocationCache> _getUserLocation() async {
    // Verificar cache
    if (_userLocationCache != null && !_userLocationCache!.isExpired) {
      return _userLocationCache!;
    }

    // Buscar do Firestore
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();

    if (!userDoc.exists || userDoc.data() == null) {
      // ⚠️ FALLBACK: Usar localização padrão (São Paulo) se documento não existe
      debugPrint('⚠️ LocationQueryService: Documento do usuário não encontrado, usando localização padrão');
      
      _userLocationCache = UserLocationCache(
        latitude: -23.5505,
        longitude: -46.6333,
        timestamp: DateTime.now(),
      );
      
      return _userLocationCache!;
    }

    final data = userDoc.data()!;
    final latitude = data['latitude'] as double?;
    final longitude = data['longitude'] as double?;

    if (latitude == null || longitude == null) {
      // ⚠️ FALLBACK: Usar localização padrão se campos não existem
      debugPrint('⚠️ LocationQueryService: Campos de localização não encontrados, usando localização padrão');
      
      _userLocationCache = UserLocationCache(
        latitude: -23.5505,
        longitude: -46.6333,
        timestamp: DateTime.now(),
      );
      
      return _userLocationCache!;
    }

    // Atualizar cache
    _userLocationCache = UserLocationCache(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
    );

    return _userLocationCache!;
  }

  /// Busca raio do usuário
  Future<double> _getUserRadius() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return 25.0; // Default

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final radiusKm = userDoc.data()!['radiusKm'] as double?;
        return radiusKm ?? 25.0;
      }
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao buscar raio: $e');
    }

    return 25.0; // Default
  }

  /// Inicializa dados de localização do usuário no Firestore
  /// 
  /// Útil para garantir que os campos necessários existem
  Future<void> initializeUserLocation({
    required double latitude,
    required double longitude,
    double? radiusKm,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'latitude': latitude,
        'longitude': longitude,
        'radiusKm': radiusKm ?? 25.0,
        'radiusUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ LocationQueryService: Dados de localização inicializados');
      
      // Invalidar cache para forçar reload
      _invalidateLocationCache();
    } catch (e) {
      debugPrint('❌ LocationQueryService: Erro ao inicializar localização: $e');
    }
  }

  /// Query Firestore com bounding box (primeira filtragem)
  Future<List<EventLocation>> _filterByBoundingBox(
    Map<String, double> boundingBox,
  ) async {
    final eventsQuery = await FirebaseFirestore.instance
        .collection('events')
        .where('latitude', isGreaterThanOrEqualTo: boundingBox['minLat'])
        .where('latitude', isLessThanOrEqualTo: boundingBox['maxLat'])
        .get();

    final events = <EventLocation>[];

    for (final doc in eventsQuery.docs) {
      final data = doc.data();
      final latitude = data['latitude'] as double?;
      final longitude = data['longitude'] as double?;

      if (latitude != null && longitude != null) {
        // Filtro adicional de longitude (Firestore só permite 1 range query)
        if (longitude >= boundingBox['minLng']! &&
            longitude <= boundingBox['maxLng']!) {
          events.add(
            EventLocation(
              eventId: doc.id,
              latitude: latitude,
              longitude: longitude,
              eventData: data,
            ),
          );
        }
      }
    }

    debugPrint(
        '📦 LocationQueryService: ${events.length} eventos candidatos do Firestore (Bounding Box)');

    return events;
  }

  /// Busca criadores e unifica com eventos
  Future<List<EventLocation>> _enrichEventsWithCreators(List<EventLocation> events) async {
    if (events.isEmpty) return [];

    // Extrair IDs dos criadores
    final creatorIds = events
        .map((e) => e.eventData['creatorId'] as String?)
        .where((id) => id != null)
        .cast<String>()
        .toSet()
        .toList();

    if (creatorIds.isEmpty) return events;

    // Buscar criadores em batches (limite de 30 do Firestore para 'in')
    final creatorsMap = <String, Map<String, dynamic>>{};
    final chunks = _chunkList(creatorIds, 30);

    for (final chunk in chunks) {
      try {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in query.docs) {
          creatorsMap[doc.id] = doc.data();
        }
      } catch (e) {
        debugPrint('❌ Erro ao buscar batch de criadores: $e');
      }
    }

    // Unificar dados
    final enrichedEvents = <EventLocation>[];
    for (final event in events) {
      final creatorId = event.eventData['creatorId'] as String?;
      if (creatorId != null && creatorsMap.containsKey(creatorId)) {
        // Criar cópia dos dados do evento e adicionar dados do criador
        final newEventData = Map<String, dynamic>.from(event.eventData);
        newEventData['creator'] = creatorsMap[creatorId];
        
        enrichedEvents.add(EventLocation(
          eventId: event.eventId,
          latitude: event.latitude,
          longitude: event.longitude,
          eventData: newEventData,
        ));
      } else {
        // Se não achou criador, mantém evento original (ou descarta? Vamos manter por segurança)
        enrichedEvents.add(event);
      }
    }

    return enrichedEvents;
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, (i + chunkSize) > list.length ? list.length : (i + chunkSize)));
    }
    return chunks;
  }

  // --- FILTROS EM MEMÓRIA (Baseados no Criador) ---

  List<EventLocation> _filterByGender(List<EventLocation> events, String? gender) {
    if (gender == null || gender == 'all') return events;
    
    return events.where((e) {
      final creator = e.eventData['creator'] as Map<String, dynamic>?;
      if (creator == null) return false; // Se filtrar por gênero e não tem criador, remove
      return creator['gender'] == gender;
    }).toList();
  }

  List<EventLocation> _filterByAge(List<EventLocation> events, int? min, int? max) {
    if (min == null && max == null) return events;
    
    return events.where((e) {
      final creator = e.eventData['creator'] as Map<String, dynamic>?;
      if (creator == null) return false;

      // Calcular idade baseada na data de nascimento (assumindo 'birthDate' timestamp ou string)
      // Simplificação: assumindo que já existe um campo 'age' ou calculando aqui
      // Se for timestamp:
      // final birthDate = (creator['birthDate'] as Timestamp?)?.toDate();
      // if (birthDate == null) return false;
      // final age = _calculateAge(birthDate);
      
      // Para este exemplo, vamos assumir que existe um campo 'age' no user profile
      // ou que calculamos previamente. Vamos tentar ler 'age'.
      final age = creator['age'] as int?;
      if (age == null) return false;
      
      final userMin = min ?? 0;
      final userMax = max ?? 100;
      
      return age >= userMin && age <= userMax;
    }).toList();
  }

  List<EventLocation> _filterByVerified(List<EventLocation> events, bool? isVerified) {
    if (isVerified == null || !isVerified) return events;
    
    return events.where((e) {
      final creator = e.eventData['creator'] as Map<String, dynamic>?;
      if (creator == null) return false;
      return creator['isVerified'] == true;
    }).toList();
  }

  List<EventLocation> _filterByInterests(List<EventLocation> events, List<String>? interests) {
    if (interests == null || interests.isEmpty) return events;
    
    return events.where((e) {
      final creator = e.eventData['creator'] as Map<String, dynamic>?;
      if (creator == null) return false;
      
      final creatorInterests = List<String>.from(creator['interests'] ?? []);
      // Retorna true se tiver pelo menos um interesse em comum
      return creatorInterests.any((i) => interests.contains(i));
    }).toList();
  }

  /// Filtra eventos com isolate (segunda filtragem precisa)
  Future<List<EventWithDistance>> _filterByDistanceIsolate({
    required List<EventLocation> events,
    required double centerLat,
    required double centerLng,
    required double radiusKm,
  }) async {
    if (events.isEmpty) return [];

    final request = DistanceFilterRequest(
      events: events,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radiusKm,
    );

    // Usar compute() para executar em isolate
    final filteredEvents = await compute(filterEventsByDistance, request);

    debugPrint(
        '🎯 LocationQueryService: ${filteredEvents.length} eventos filtrados por distância (Isolate)');

    return filteredEvents;
  }

  /// Invalida cache de localização
  void _invalidateLocationCache() {
    _userLocationCache = null;
    debugPrint('🗑️ LocationQueryService: Cache de localização invalidado');
  }

  /// Invalida cache de eventos
  void _invalidateEventsCache() {
    _eventsCache = null;
    debugPrint('🗑️ LocationQueryService: Cache de eventos invalidado');
  }

  /// Invalida todos os caches
  void _invalidateAllCaches() {
    _invalidateLocationCache();
    _invalidateEventsCache();
  }

  /// Força reload manual
  void forceReload() {
    _invalidateAllCaches();
    _loadAndEmitEvents();
  }

  /// Dispose
  void dispose() {
    _eventsStreamController.close();
  }
}

/// Cache de localização do usuário
class UserLocationCache {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  UserLocationCache({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  /// Verifica se o cache está expirado
  bool get isExpired {
    return DateTime.now().difference(timestamp) >
        LocationQueryService.cacheTTL;
  }
}

/// Cache de eventos
class EventsCache {
  final List<EventWithDistance> events;
  final double radiusKm;
  final DateTime timestamp;

  EventsCache({
    required this.events,
    required this.radiusKm,
    required this.timestamp,
  });

  /// Verifica se o cache está expirado
  bool get isExpired {
    return DateTime.now().difference(timestamp) >
        LocationQueryService.cacheTTL;
  }
}

/// Opções de filtro para eventos
class EventFilterOptions {
  final String? gender;
  final int? minAge;
  final int? maxAge;
  final bool? isVerified;
  final List<String>? interests;

  EventFilterOptions({
    this.gender,
    this.minAge,
    this.maxAge,
    this.isVerified,
    this.interests,
  });
}
