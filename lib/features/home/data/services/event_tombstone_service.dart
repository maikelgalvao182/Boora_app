import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/geohash_helper.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';

/// Serviço de polling delta de tombstones para detectar deleções/desativações
/// de eventos de forma eficiente.
///
/// Ao invés de manter um snapshot listener caro no `events_card_preview`,
/// fazemos polling leve na coleção `event_tombstones`:
///
///   where regionKey in [prefixes de geohash]
///   where deletedAt > lastSeenDeletedAt
///   orderBy deletedAt
///   limit(50)
///
/// Resultado típico: 0-poucos docs por poll, custo mínimo.
///
/// Frequência controlada: chamado em `onCameraIdle` (com debounce),
/// ou a cada ~30s enquanto o mapa estiver aberto.
class EventTombstoneService {
  // Singleton
  static final EventTombstoneService _instance =
      EventTombstoneService._internal();
  factory EventTombstoneService() => _instance;
  EventTombstoneService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'event_tombstones';

  /// Precisão do geohash para regionKey (4 chars = ~40km x 20km).
  /// Deve coincidir com a precisão usada no Cloud Function.
  static const int _geohashPrecision = 4;

  /// Máximo de tombstones por poll (safety limit).
  static const int _maxTombstonesPerPoll = 50;

  /// Intervalo mínimo entre polls (evita spam durante pans rápidos).
  static const Duration minPollInterval = Duration(seconds: 10);

  /// Intervalo do timer periódico (background, enquanto mapa aberto).
  static const Duration periodicPollInterval = Duration(seconds: 30);

  /// Último timestamp visto por regionKey.
  /// Mantém em memória — ao reiniciar o app, faz um poll mais amplo
  /// (mas como o cache local também reinicia, isso é correto).
  final Map<String, DateTime> _lastSeenByRegion = {};

  /// Timestamp do último poll (evita polls muito frequentes).
  DateTime _lastPollAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Timer periódico (opcional, ativado enquanto o mapa está visível).
  Timer? _periodicTimer;

  /// Bounds do último poll (para saber quais regionKeys usar no timer).
  MapBounds? _lastPollBounds;

  /// Stream que emite IDs de eventos deletados detectados por polling.
  final StreamController<String> _deletionDetectedController =
      StreamController<String>.broadcast();
  Stream<String> get onEventDeletionDetected =>
      _deletionDetectedController.stream;

  /// Executa um poll de tombstones para a região visível do mapa.
  ///
  /// Retorna a lista de eventIds deletados detectados (pode ser vazia).
  /// Apenas novos tombstones (desde o último poll) são retornados.
  Future<List<String>> pollTombstones(MapBounds bounds) async {
    // Rate-limit
    final now = DateTime.now();
    if (now.difference(_lastPollAt) < minPollInterval) {
      return const [];
    }
    _lastPollAt = now;
    _lastPollBounds = bounds;

    // Calcular regionKeys (geohash prefixes) que cobrem o viewport.
    final regionKeys = _regionKeysForBounds(bounds);
    if (regionKeys.isEmpty) return const [];

    // Firestore `whereIn` aceita no máximo 30 valores.
    // Com geohash 4-chars cobrindo ~40km, um viewport grande pode ter
    // mais de 30 prefixes. Agrupamos em batches de 30.
    final deletedIds = <String>[];

    for (var i = 0; i < regionKeys.length; i += 30) {
      final batch = regionKeys.sublist(
        i,
        i + 30 > regionKeys.length ? regionKeys.length : i + 30,
      );

      // Usar o timestamp mais antigo entre as regions do batch.
      DateTime? oldest;
      for (final key in batch) {
        final seen = _lastSeenByRegion[key];
        if (seen == null || (oldest != null && seen.isBefore(oldest))) {
          oldest = seen;
        }
        oldest ??= seen;
      }

      // Se nunca vimos essa região, buscar os últimos 10 minutos
      // (cobre o TTL máximo de cache persistente).
      oldest ??= now.subtract(const Duration(minutes: 10));

      try {
        final snapshot = await _firestore
            .collection(_collection)
            .where('regionKey', whereIn: batch)
            .where('deletedAt', isGreaterThan: Timestamp.fromDate(oldest))
            .orderBy('deletedAt')
            .limit(_maxTombstonesPerPoll)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final eventId = data['eventId'] as String?;
          final deletedAt = data['deletedAt'] as Timestamp?;
          final regionKey = data['regionKey'] as String?;

          if (eventId == null) continue;

          deletedIds.add(eventId);

          // Atualiza lastSeen para a regionKey deste tombstone
          if (regionKey != null && deletedAt != null) {
            final ts = deletedAt.toDate();
            final current = _lastSeenByRegion[regionKey];
            if (current == null || ts.isAfter(current)) {
              _lastSeenByRegion[regionKey] = ts;
            }
          }
        }

        if (snapshot.docs.isNotEmpty) {
          debugPrint(
            '💀 [TombstoneService] Poll: ${snapshot.docs.length} tombstones '
            'em ${batch.length} regions',
          );
        }
      } catch (e) {
        debugPrint('⚠️ [TombstoneService] Erro no poll: $e');
      }
    }

    // Emite no stream para cada ID deletado
    for (final eventId in deletedIds) {
      _deletionDetectedController.add(eventId);
    }

    return deletedIds;
  }

  /// Gera os geohash prefixes (4 chars) que cobrem um MapBounds.
  ///
  /// Estratégia: rasteriza a bounding box com step de ~0.2° (~22km)
  /// e coleta os geohash prefixes únicos.
  List<String> _regionKeysForBounds(MapBounds bounds) {
    final keys = <String>{};

    // Step size em graus — metade do tamanho de um tile de geohash-4
    // Geohash 4 chars ≈ 40km de largura × 20km de altura
    // → step ≈ 0.18° lat (20km / 111km), 0.36° lng (40km / 111km)
    const latStep = 0.18;
    const lngStep = 0.36;

    var lat = bounds.minLat;
    while (lat <= bounds.maxLat) {
      var lng = bounds.minLng;
      while (lng <= bounds.maxLng) {
        final hash = GeohashHelper.encode(lat, lng, precision: _geohashPrecision);
        if (hash.isNotEmpty) {
          keys.add(hash);
        }
        lng += lngStep;
      }
      // Garante que o canto superior direito é incluído
      final cornerHash = GeohashHelper.encode(lat, bounds.maxLng, precision: _geohashPrecision);
      if (cornerHash.isNotEmpty) keys.add(cornerHash);
      lat += latStep;
    }

    // Garante que os 4 cantos estão incluídos
    for (final corner in [
      [bounds.minLat, bounds.minLng],
      [bounds.minLat, bounds.maxLng],
      [bounds.maxLat, bounds.minLng],
      [bounds.maxLat, bounds.maxLng],
    ]) {
      final h = GeohashHelper.encode(corner[0], corner[1], precision: _geohashPrecision);
      if (h.isNotEmpty) keys.add(h);
    }

    return keys.toList(growable: false);
  }

  /// Inicia o timer periódico de polling (enquanto o mapa está visível).
  ///
  /// O timer re-poll a cada [periodicPollInterval] usando o último
  /// bounds conhecido. Isso garante que mesmo sem movimentar o mapa,
  /// deleções são detectadas em ~30s.
  void startPeriodicPolling() {
    stopPeriodicPolling();
    _periodicTimer = Timer.periodic(periodicPollInterval, (_) {
      final bounds = _lastPollBounds;
      if (bounds == null) return;
      pollTombstones(bounds);
    });
    debugPrint('⏱️ [TombstoneService] Polling periódico iniciado (${periodicPollInterval.inSeconds}s)');
  }

  /// Para o timer periódico.
  void stopPeriodicPolling() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Limpa estado (ex: logout).
  void reset() {
    stopPeriodicPolling();
    _lastSeenByRegion.clear();
    _lastPollBounds = null;
    _lastPollAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Dispose completo.
  void dispose() {
    reset();
    _deletionDetectedController.close();
  }
}
