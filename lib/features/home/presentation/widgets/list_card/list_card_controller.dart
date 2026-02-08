import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:partiu/core/services/cache/app_cache_service.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Controller para gerenciar dados do ListCard
class ListCardController extends ChangeNotifier {
  final EventRepository _eventRepo;
  final EventApplicationRepository _applicationRepo;
  final UserRepository _userRepo;
  final String eventId;

  // Event data
  String? _emoji;
  String? _activityText;
  String? _locationName;
  String? _locality;
  String? _state;
  DateTime? _scheduleDate;
  String? _creatorId;

  // Creator data
  String? _creatorPhotoUrl;

  // Participants data (últimos 5)
  List<Map<String, dynamic>> _recentParticipants = [];
  int _totalParticipantsCount = 0;

  bool _loaded = false;
  bool _isLoading = false;
  String? _error;
  
  // ValueNotifiers para rebuild granular
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> dataReadyNotifier = ValueNotifier(false);

  ListCardController({
    required this.eventId,
    EventRepository? eventRepo,
    EventApplicationRepository? applicationRepo,
    UserRepository? userRepo,
  })  : _eventRepo = eventRepo ?? EventRepository(),
        _applicationRepo = applicationRepo ?? EventApplicationRepository(),
        _userRepo = userRepo ?? UserRepository();

  // Getters
  String? get emoji => _emoji;
  String? get activityText => _activityText;
  String? get locationName => _locationName;
  String? get locality => _locality;
  String? get state => _state;
  DateTime? get scheduleDate => _scheduleDate;
  String? get creatorId => _creatorId;
  String? get creatorPhotoUrl => _creatorPhotoUrl;
  List<Map<String, dynamic>> get recentParticipants => _recentParticipants;
  int get totalParticipantsCount => _totalParticipantsCount;
  bool get isLoading => !_loaded && _error == null;
  String? get error => _error;
  bool get hasData => _loaded && _error == null;

  /// Carrega todos os dados necessários para o card
  Future<void> load() async {
    // Se já carregou ou está carregando, não faz nada
    if (_loaded || _isLoading) return;
    
    _isLoading = true;
    loadingNotifier.value = true;
    
    try {
      // Carregar dados do evento e participantes em paralelo
      final results = await Future.wait([
        _eventRepo.getEventBasicInfo(eventId),
        _applicationRepo.getRecentApplicationsWithUserData(eventId, limit: 5),
        _applicationRepo.getApprovedApplicationsCount(eventId),
      ]);

      // Parse event data
      final eventData = results[0] as Map<String, dynamic>?;
      if (eventData == null) {
        _error = 'Atividade indisponível';
        _loaded = false;
        _isLoading = false;
        loadingNotifier.value = false;
        dataReadyNotifier.value = false;
        notifyListeners();
        return;
      }

      _emoji = eventData['emoji'] as String?;
      _activityText = eventData['activityText'] as String?;
      _locationName = eventData['locationName'] as String?;
      _locality = eventData['locality'] as String?;
      _state = eventData['state'] as String?;
      _scheduleDate = eventData['scheduleDate'] as DateTime?;
      _creatorId = eventData['createdBy'] as String?;
      
      // Buscar dados do criador (photoUrl)
      if (_creatorId != null) {
        final creatorData = await _userRepo.getUserBasicInfo(_creatorId!);
        _creatorPhotoUrl = creatorData?['photoUrl'] as String?;
      }

      // Parse participants data
      _recentParticipants = results[1] as List<Map<String, dynamic>>;
      _totalParticipantsCount = results[2] as int;
      
      // ✅ PRELOAD: Carregar avatares antes da UI renderizar
      if (_creatorId != null && _creatorPhotoUrl != null && _creatorPhotoUrl!.isNotEmpty) {
        UserStore.instance.preloadAvatar(_creatorId!, _creatorPhotoUrl!);
      }
      for (final participant in _recentParticipants) {
        final pUserId = participant['userId'] as String?;
        final pPhotoUrl = participant['photoUrl'] as String?;
        if (pUserId != null && pPhotoUrl != null && pPhotoUrl.isNotEmpty) {
          UserStore.instance.preloadAvatar(pUserId, pPhotoUrl);
        }
      }

      _loaded = true;
      _isLoading = false;
      loadingNotifier.value = false;
      dataReadyNotifier.value = true;
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao carregar dados: $e';
      _loaded = false;
      _isLoading = false;
      loadingNotifier.value = false;
      notifyListeners();
      debugPrint('❌ Erro no ListCardController: $e');
    }
  }

  /// Recarrega os dados
  Future<void> refresh() async {
    _loaded = false;
    _error = null;
    notifyListeners();
    await load();
  }

  /// 🎯 Aguarda até que os dados E avatares estejam carregados
  /// Chamar ANTES de exibir o card em listas para evitar "pop" dos avatares
  Future<void> ensureDataAndAvatarsLoaded() async {
    await load();
    await preloadAvatarsAsync();
  }

  /// Aguarda o download real dos avatares dos participantes
  /// 
  /// Use ANTES de exibir o ListCard para garantir que os avatares
  /// apareçam imediatamente, sem "popping".
  Future<void> preloadAvatarsAsync() async {
    final futures = <Future<void>>[];

    // Avatar do criador
    if (_creatorPhotoUrl != null && _creatorPhotoUrl!.isNotEmpty) {
      futures.add(_downloadImage(_creatorPhotoUrl!));
    }

    // Avatares dos participantes
    for (final p in _recentParticipants) {
      final photoUrl = p['photoUrl'] as String?;
      if (photoUrl != null && photoUrl.isNotEmpty) {
        futures.add(_downloadImage(photoUrl));
      }
    }

    if (futures.isEmpty) return;

    // Aguarda todos os avatares (com timeout de 3s para não travar UI)
    await Future.wait(futures).timeout(
      const Duration(seconds: 3),
      onTimeout: () => [], // Timeout silencioso
    );
  }

  /// Força o download de uma imagem para o cache
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
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout silencioso
    } finally {
      stream.removeListener(listener);
    }
  }
}
