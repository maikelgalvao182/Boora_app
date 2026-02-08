import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:partiu/core/services/cache/app_cache_service.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Serviço para pré-carregar avatares de participantes dos eventos visíveis.
///
/// Otimiza a UX do EventCard e ListCard ao garantir que os avatares
/// já estejam no cache quando o usuário abrir um card.
///
/// Uso recomendado:
/// - Chamar após `onFirstRenderApplied` do mapa (com pequeno delay)
/// - Chamar em background com baixa prioridade
class ParticipantAvatarWarmupService {
  ParticipantAvatarWarmupService({
    EventApplicationRepository? applicationRepo,
  }) : _applicationRepo = applicationRepo ?? EventApplicationRepository();

  final EventApplicationRepository _applicationRepo;

  /// Flag para evitar múltiplos warmups simultâneos
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Cancellation token (para interromper warmup em progresso)
  bool _shouldCancel = false;

  /// Eventos que já foram aquecidos (evita retrabalho)
  final Set<String> _warmedUpEvents = {};

  /// Limite de eventos para aquecer por ciclo
  static const int _maxEventsPerCycle = 15;

  /// Limite de participantes por evento
  static const int _participantsPerEvent = 5;

  /// Timeout por imagem para não travar o warmup
  static const Duration _imageTimeout = Duration(seconds: 3);

  /// Cancela qualquer warmup em progresso
  void cancel() {
    _shouldCancel = true;
  }

  /// Limpa o cache de eventos já aquecidos
  void clearCache() {
    _warmedUpEvents.clear();
  }

  /// Aquece avatares de participantes para uma lista de eventos.
  ///
  /// - Busca os N primeiros participantes de cada evento
  /// - Faz preload dos avatares via UserStore
  /// - É best-effort: erros são ignorados silenciosamente
  ///
  /// [events] Lista de eventos visíveis no mapa
  /// [maxEvents] Máximo de eventos para processar (default: 15)
  /// [participantsPerEvent] Máximo de participantes por evento (default: 5)
  Future<void> warmupParticipantsForEvents(
    List<EventModel> events, {
    int? maxEvents,
    int? participantsPerEvent,
  }) async {
    if (_isRunning) {
      debugPrint('⏳ [AvatarWarmup] Já está rodando, ignorando chamada');
      return;
    }

    if (events.isEmpty) return;

    final effectiveMaxEvents = maxEvents ?? _maxEventsPerCycle;
    final effectiveParticipantsLimit = participantsPerEvent ?? _participantsPerEvent;

    _isRunning = true;
    _shouldCancel = false;

    try {
      // Filtrar eventos que ainda não foram aquecidos
      final eventsToWarmup = events
          .where((e) => !_warmedUpEvents.contains(e.id))
          .take(effectiveMaxEvents)
          .toList();

      if (eventsToWarmup.isEmpty) {
        debugPrint('✅ [AvatarWarmup] Todos os eventos já foram aquecidos');
        return;
      }

      debugPrint(
        '🔥 [AvatarWarmup] Iniciando warmup de ${eventsToWarmup.length} eventos',
      );

      int totalAvatarsWarmed = 0;

      // Processar eventos sequencialmente para não sobrecarregar
      for (final event in eventsToWarmup) {
        if (_shouldCancel) {
          debugPrint('⚠️ [AvatarWarmup] Cancelado pelo usuário');
          break;
        }

        try {
          final participants = await _applicationRepo.getRecentApplicationsWithUserData(
            event.id,
            limit: effectiveParticipantsLimit,
          );

          // Coletar todas as URLs para download em paralelo (por evento)
          final downloadFutures = <Future<void>>[];

          // Avatares dos participantes
          for (final p in participants) {
            final userId = p['userId'] as String?;
            final photoUrl = p['photoUrl'] as String?;

            if (userId != null &&
                userId.isNotEmpty &&
                photoUrl != null &&
                photoUrl.isNotEmpty) {
              // Registra no UserStore (metadados)
              UserStore.instance.preloadAvatar(userId, photoUrl);
              // Força download real da imagem
              downloadFutures.add(_downloadImage(photoUrl));
              totalAvatarsWarmed++;
            }
          }

          // Também o criador (se tiver)
          final creatorId = event.createdBy;
          final creatorUrl = event.creatorAvatarUrl;
          if (creatorId.isNotEmpty) {
            if (creatorUrl != null && creatorUrl.isNotEmpty) {
              UserStore.instance.preloadAvatar(creatorId, creatorUrl);
              downloadFutures.add(_downloadImage(creatorUrl));
              totalAvatarsWarmed++;
            } else {
              // ✅ creatorAvatarUrl não está em events_card_preview,
              // então resolvemos via UserStore (fetch do Users/{id})
              UserStore.instance.resolveUser(creatorId);
            }
          }

          // Aguardar downloads deste evento (com timeout global por evento)
          if (downloadFutures.isNotEmpty) {
            await Future.wait(downloadFutures).timeout(
              const Duration(seconds: 5),
              onTimeout: () => [], // Timeout silencioso
            );
          }

          _warmedUpEvents.add(event.id);
        } catch (e) {
          // Erro por evento é ignorado silenciosamente
          debugPrint('⚠️ [AvatarWarmup] Erro no evento ${event.id}: $e');
        }

        // Pequeno yield para não travar UI
        await Future.delayed(const Duration(milliseconds: 10));
      }

      debugPrint(
        '✅ [AvatarWarmup] Finalizado: $totalAvatarsWarmed avatares aquecidos de ${eventsToWarmup.length} eventos',
      );
    } finally {
      _isRunning = false;
      _shouldCancel = false;
    }
  }

  /// Força o download de uma imagem para o cache de disco/memória.
  /// 
  /// Usa o mesmo CacheManager do app para garantir consistência.
  Future<void> _downloadImage(String url) async {
    final imageProvider = CachedNetworkImageProvider(
      url,
      cacheManager: AppCacheService.instance.avatarCacheManager,
      cacheKey: AppCacheService.instance.avatarCacheKey(url),
    );
    
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    final completer = Completer<void>();

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (error, __) {
        if (!completer.isCompleted) completer.complete();
      },
    );

    stream.addListener(listener);

    try {
      await completer.future.timeout(_imageTimeout);
    } catch (_) {
      // Timeout silencioso
    } finally {
      stream.removeListener(listener);
    }
  }

  /// Verifica se um evento já foi aquecido
  bool isEventWarmedUp(String eventId) => _warmedUpEvents.contains(eventId);
}
