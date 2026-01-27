import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:partiu/features/home/data/models/event_location.dart';
import 'package:partiu/features/home/data/models/event_location_cache.dart';

/// Repository para cache persistente de eventos do mapa
/// 
/// 🧠 Filosofia: Hive não é banco local. É acelerador de UI.
/// - "Isso ajuda o app a PARECER rápido?" → Hive ✅
/// - "Isso define a verdade?" → Firestore
/// 
/// Estratégia: Stale-While-Revalidate
/// 1. Mostra cache imediatamente (UI rápida)
/// 2. Busca dados frescos do Firestore em background
/// 3. Atualiza UI quando dados chegam
/// 
/// Estrutura do cache:
/// - Chave: quadkey (tile do mapa)
/// - Valor: Lista de EventLocationCache
/// - TTL: 20 minutos (invalidação ativa quando bounds mudam)
class EventCacheRepository {
  static final EventCacheRepository _instance = EventCacheRepository._internal();
  factory EventCacheRepository() => _instance;
  EventCacheRepository._internal();

  static const String _boxName = 'event_locations';
  static const String _metaBoxName = 'event_locations_meta';
  
  /// TTL padrão: 20 minutos
  /// 
  /// Por que longo? Eventos não mudam de lugar. Mapa vazio no cold start
  /// é MUITO pior que marker levemente desatualizado.
  /// Invalidação natural ocorre quando: bounds mudam, stream chega, ação do usuário.
  static const Duration defaultTTL = Duration(minutes: 20);

  Box<List<dynamic>>? _box;
  Box<int>? _metaBox;
  bool _initialized = false;
  bool debugMode = false;

  bool get isInitialized => _initialized;

  /// Inicializa o repository
  /// 
  /// Deve ser chamado após HiveInitializer.initialize()
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Registra adapter se ainda não registrado
      if (!Hive.isAdapterRegistered(10)) {
        Hive.registerAdapter(EventLocationCacheAdapter());
      }

      _box = await Hive.openBox<List<dynamic>>(_boxName);
      _metaBox = await Hive.openBox<int>(_metaBoxName);
      _initialized = true;

      _log('Initialized (${_box!.length} quadkeys cached)');

      // Limpa entradas expiradas no startup
      await _clearExpired();
    } catch (e) {
      debugPrint('📦 EventCacheRepository: Init error: $e');
      // Não propaga - cache é opcional
    }
  }

  /// Recupera eventos do cache para um quadkey
  /// 
  /// Retorna null se:
  /// - Cache não inicializado
  /// - Quadkey não existe
  /// - Entrada expirou
  List<EventLocation>? getEvents(String quadkey) {
    if (!_initialized || _box == null) return null;

    // Verifica TTL
    final expiresAt = _metaBox?.get(quadkey);
    if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
      // Expirado - remove e retorna null
      _box!.delete(quadkey);
      _metaBox!.delete(quadkey);
      _log('EXPIRED: $quadkey');
      return null;
    }

    final cached = _box!.get(quadkey);
    if (cached == null) {
      _log('MISS: $quadkey');
      return null;
    }

    try {
      // Converte de volta para EventLocation
      final events = cached
          .cast<EventLocationCache>()
          .map((c) => EventLocation(
                eventId: c.eventId,
                latitude: c.latitude,
                longitude: c.longitude,
                eventData: c.toMinimalEventData(),
              ))
          .toList();

      _log('HIT: $quadkey (${events.length} eventos)');
      return events;
    } catch (e) {
      _log('ERROR reading: $quadkey - $e');
      // Cache corrompido - remove
      _box!.delete(quadkey);
      _metaBox!.delete(quadkey);
      return null;
    }
  }

  /// Salva eventos no cache para um quadkey
  /// 
  /// [quadkey] - Identificador do tile do mapa
  /// [events] - Lista de EventLocation do Firestore
  /// [ttl] - Tempo de vida (padrão: 20 minutos)
  Future<void> saveEvents(
    String quadkey,
    List<EventLocation> events, {
    Duration ttl = defaultTTL,
  }) async {
    if (!_initialized || _box == null) return;

    try {
      // Converte para modelo de cache
      final cacheList = events
          .map((e) => EventLocationCache.fromEventLocation(
                e.eventId,
                e.latitude,
                e.longitude,
                e.eventData,
              ))
          .toList();

      final expiresAt = DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;

      await _box!.put(quadkey, cacheList);
      await _metaBox!.put(quadkey, expiresAt);

      _log('SAVED: $quadkey (${events.length} eventos, TTL: ${ttl.inMinutes}min)');
    } catch (e) {
      _log('ERROR saving: $quadkey - $e');
    }
  }

  /// Remove um evento específico de todos os quadkeys
  /// 
  /// Usado após deleção de evento para manter consistência
  Future<void> removeEvent(String eventId) async {
    if (!_initialized || _box == null) return;

    var removedCount = 0;

    for (final key in _box!.keys.cast<String>().toList()) {
      final cached = _box!.get(key);
      if (cached == null) continue;

      try {
        final list = cached.cast<EventLocationCache>();
        final filtered = list.where((e) => e.eventId != eventId).toList();

        if (filtered.length != list.length) {
          await _box!.put(key, filtered);
          removedCount++;
        }
      } catch (_) {}
    }

    if (removedCount > 0) {
      _log('REMOVED event $eventId from $removedCount quadkeys');
    }
  }

  /// Invalida um quadkey específico
  Future<void> invalidate(String quadkey) async {
    if (!_initialized) return;

    await _box?.delete(quadkey);
    await _metaBox?.delete(quadkey);
    _log('INVALIDATED: $quadkey');
  }

  /// Limpa todo o cache
  Future<void> clear() async {
    if (!_initialized) return;

    final count = _box?.length ?? 0;
    await _box?.clear();
    await _metaBox?.clear();
    _log('CLEARED: $count quadkeys');
  }

  /// Limpa entradas expiradas
  Future<int> _clearExpired() async {
    if (!_initialized || _metaBox == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredKeys = <String>[];

    for (final key in _metaBox!.keys.cast<String>()) {
      final expiresAt = _metaBox!.get(key);
      if (expiresAt != null && expiresAt < now) {
        expiredKeys.add(key);
      }
    }

    for (final key in expiredKeys) {
      await _box?.delete(key);
      await _metaBox?.delete(key);
    }

    if (expiredKeys.isNotEmpty) {
      _log('CLEANUP: ${expiredKeys.length} expired quadkeys removed');
    }

    return expiredKeys.length;
  }

  /// Retorna todos os quadkeys válidos (não expirados)
  List<String> get cachedQuadkeys {
    if (!_initialized || _box == null) return [];

    final now = DateTime.now().millisecondsSinceEpoch;
    return _box!.keys.cast<String>().where((key) {
      final expiresAt = _metaBox?.get(key);
      return expiresAt == null || expiresAt > now;
    }).toList();
  }

  /// Número de quadkeys no cache
  int get length => cachedQuadkeys.length;

  /// Fecha o repository
  Future<void> close() async {
    await _box?.close();
    await _metaBox?.close();
    _initialized = false;
    _log('CLOSED');
  }

  void _log(String message) {
    if (debugMode) {
      debugPrint('📦 EventCache: $message');
    }
  }
}
