import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/utils/date_formatter.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';

/// Controller para gerenciar dados do EventCard
class EventCardController extends ChangeNotifier {
  final FirebaseAuth _auth;
  final EventApplicationRepository _applicationRepo;
  final EventRepository _eventRepo;
  final UserRepository _userRepo;
  final String eventId;
  final EventModel? _preloadedEvent;

  // STREAMS realtime
  StreamSubscription<QuerySnapshot>? _applicationSub;
  StreamSubscription<DocumentSnapshot>? _eventSub;
  StreamSubscription<QuerySnapshot>? _participantsSub;
  // Stream do snapshot de participantes para reaproveitar em widgets sem criar
  // listeners adicionais por card.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _participantsSnapshotStream;
  StreamSubscription<User?>? _authSub;
  bool _listenersInitialized = false;

  // Dados
  String? _creatorFullName;
  String? _locationName;
  String? _emoji;
  String? _activityText;
  DateTime? _scheduleDate;
  String? _privacyType;
  String? _creatorId;
  bool _loaded = false;
  String? _error;
  bool _disposed = false;

  // Application state
  EventApplicationModel? _userApplication;
  bool _isApplying = false;
  bool _isLeaving = false;
  bool _isDeleting = false;
  
  // 🔑 Estado local autoritativo para evitar flash após leave
  // UI é fonte de verdade no curto prazo, backend no longo prazo
  bool _forceLeft = false;

  // Participants
  List<Map<String, dynamic>> _approvedParticipants = [];
  
  // Age restriction
  int? _minAge;
  int? _maxAge;
  int? _userAge;
  bool _isAgeRestricted = false;

  // Gender restriction
  String? _requiredGender;
  String? _currentUserGender;
  bool _isGenderRestricted = false;

  EventCardController({
    required this.eventId,
    EventModel? preloadedEvent,
    FirebaseAuth? auth,
    EventApplicationRepository? applicationRepo,
    EventRepository? eventRepo,
    UserRepository? userRepo,
  })  : _preloadedEvent = preloadedEvent,
        _auth = auth ?? FirebaseAuth.instance,
        _applicationRepo = applicationRepo ?? EventApplicationRepository(),
        _eventRepo = eventRepo ?? EventRepository(),
        _userRepo = userRepo ?? UserRepository() {
    _initializeFromPreload();
    // ✅ Iniciar listeners imediatamente para garantir reatividade dos botões
    _setupRealtimeListeners();
  }

  // ---------------------------------------------------------------------------
  // INITIALIZAÇÃO COM PRELOADED EVENT
  // ---------------------------------------------------------------------------

  void _initializeFromPreload() {
    debugPrint('🎫 [EventCard] _initializeFromPreload - eventId: $eventId');
    debugPrint('🎫 [EventCard] _preloadedEvent: ${_preloadedEvent != null ? "EXISTS" : "NULL"}');
    
    if (_preloadedEvent != null) {
      _emoji = _preloadedEvent!.emoji;
      _activityText = _preloadedEvent!.title;
      _locationName = _preloadedEvent!.locationName;
      _creatorFullName = _preloadedEvent!.creatorFullName;
      _scheduleDate = _preloadedEvent!.scheduleDate;
      _privacyType = _preloadedEvent!.privacyType;
      _creatorId = _preloadedEvent!.createdBy;

      _userApplication = _preloadedEvent!.userApplication;
      
      // ✅ INICIALIZAR isAgeRestricted E minAge/maxAge a partir do evento pré-carregado
      _isAgeRestricted = _preloadedEvent!.isAgeRestricted;
      _minAge = _preloadedEvent!.minAge;
      _maxAge = _preloadedEvent!.maxAge;

      // ✅ INICIALIZAR restrição de gênero
      _requiredGender = _preloadedEvent!.gender;
      // Se tiver restrição, validar o usuário
      if (_requiredGender != null && _requiredGender != GENDER_ALL) {
        _validateUserGender(_auth.currentUser?.uid ?? '');
      }

      if (_preloadedEvent!.participants != null) {
        _approvedParticipants = _preloadedEvent!.participants!;
        // Preload avatares para evitar "popping" na UI
        _preloadParticipantAvatars();
      } else {
        // ✅ Se não há participantes no preload, tentar cache (memória + Hive)
        _hydrateParticipantsFromCache();
      }

      debugPrint('🎫 [EventCard] Dados carregados:');
      debugPrint('   - emoji: $_emoji');
      debugPrint('   - activityText: $_activityText');
      debugPrint('   - locationName: $_locationName');
      debugPrint('   - creatorFullName: $_creatorFullName');
      debugPrint('   - privacyType: $_privacyType');
      debugPrint('   - creatorId: $_creatorId');

      if (_privacyType != null && _creatorId != null) {
        _loaded = true;
        debugPrint('🎫 [EventCard] ✅ _loaded = true');
        
        // ✅ Se creatorFullName está faltando, buscar em background
        if (_creatorFullName == null && _creatorId != null) {
          _fetchCreatorNameInBackground();
        }
      } else {
        debugPrint('🎫 [EventCard] ⚠️ _loaded = false (privacyType ou creatorId é null)');
      }
    } else {
      debugPrint('🎫 [EventCard] ❌ _preloadedEvent é NULL - sem dados para carregar');
    }
  }

  /// Busca participantes do cache (memória + Hive) sem bloquear a UI
  Future<void> _hydrateParticipantsFromCache() async {
    if (_disposed) return;

    try {
      final cached = await _applicationRepo.getCachedApprovedParticipants(eventId);
      if (_disposed) return;

      if (cached == null || cached.isEmpty) return;
      if (_approvedParticipants.isNotEmpty) return;

      _approvedParticipants = cached;
      _preloadParticipantAvatars();
      debugPrint('✅ [EventCard] Participantes carregados do cache (${cached.length})');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [EventCard] Erro ao hidratar participantes do cache: $e');
    }
  }
  
  /// Busca o nome do criador em background e atualiza a UI
  Future<void> _fetchCreatorNameInBackground() async {
    if (_creatorId == null || _disposed) return;
    
    try {
      final userData = await _userRepo.getUserBasicInfo(_creatorId!);
      final fullName = userData?['fullName'] as String?;
      
      if (_disposed) return;
      
      if (fullName != null && _creatorFullName == null) {
        _creatorFullName = fullName;
        debugPrint('✅ [EventCard] creatorFullName carregado em background: $fullName');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ [EventCard] Erro ao buscar nome do criador: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // GETTERS (mantidos exatamente como no seu código original)
  // ---------------------------------------------------------------------------

  String? get creatorFullName => _creatorFullName;
  String? get locationName => _locationName;
  String? get emoji => _emoji;
  String? get activityText => _activityText;
  DateTime? get scheduleDate => _scheduleDate;
  String? get privacyType => _privacyType;
  String? get creatorId => _creatorId;

  bool get isLoading => !_loaded && _error == null;
  String? get error => _error;
  bool get hasData {
    // ✅ RELAXADO: Não exige creatorFullName para mostrar o card
    // O nome pode ser carregado em background e a UI atualiza via notifyListeners
    final result = _error == null && _activityText != null;
    if (!result) {
      debugPrint('🎫 [EventCard] hasData = FALSE para eventId: $eventId');
      debugPrint('   - _error: $_error');
      debugPrint('   - _activityText: $_activityText');
    }
    return result;
  }

  EventApplicationModel? get userApplication => _userApplication;
  bool get hasApplied => !_forceLeft && _userApplication != null;
  bool get isApproved => isCreator || (_userApplication?.isApproved ?? false);
  bool get isPending => _userApplication?.isPending ?? false;
  bool get isRejected => _userApplication?.isRejected ?? false;
  bool get isApplying => _isApplying;
  bool get isLeaving => _isLeaving;
  bool get isDeleting => _isDeleting;
  bool get isCreator => _auth.currentUser?.uid == _creatorId;

  List<Map<String, dynamic>> get approvedParticipants => _approvedParticipants;
  int get participantsCount => _approvedParticipants.length;
  Stream<int> get participantsCountStream => (_participantsSnapshotStream ??
    FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('status', whereIn: ['approved', 'autoApproved'])
        .snapshots())
      .map((snapshot) => snapshot.docs.length);
  List<Map<String, dynamic>> get visibleParticipants => _approvedParticipants.take(5).toList();
  int get remainingParticipantsCount => participantsCount - visibleParticipants.length;

  String get formattedDate => DateFormatter.formatDate(_scheduleDate);
  String get formattedTime => DateFormatter.formatTime(_scheduleDate);

  Map<String, dynamic>? get locationData {
    if (_preloadedEvent == null) return null;

    return {
      'locationName': _preloadedEvent!.locationName,
      'formattedAddress': _preloadedEvent!.formattedAddress,
      'placeId': _preloadedEvent!.placeId,
      'photoReferences': _preloadedEvent!.photoReferences,
      'visitors': _approvedParticipants.take(3).toList(),
      'totalVisitorsCount': _approvedParticipants.length,
    };
  }

  String get buttonText {
    if (isCreator) return 'view_participants';
    if (isApplying) return 'applying';
    if (isApproved) return 'view_event_chat';
    if (isPending) return 'awaiting_approval';
    if (isRejected) return 'application_rejected';

    if (_preloadedEvent != null && !_preloadedEvent!.isAvailable) {
      return 'out_of_your_area';
    }
    
    // ✅ RETORNAR mensagem de restrição de idade
    if (_isAgeRestricted) {
      return 'age_restricted'; // Ou retornar direto: 'Indisponível para sua idade'
    }

    if (_isGenderRestricted) {
      return _genderRestrictionButtonTextKey;
    }

    return privacyType == 'open' ? 'participate' : 'request_participation';
  }

  String get chatButtonText => 'Chat';
  String get leaveButtonText => 'Sair';
  String get deleteButtonText => 'Deletar';

  bool get isButtonEnabled {
    if (isCreator) return true;
    if (isApplying || isLeaving || isDeleting) return false;
    if (isApproved) return true;
    if (isPending || isRejected) return false;

    if (_preloadedEvent != null && !_preloadedEvent!.isAvailable) {
      return false;
    }
    
    // ✅ BLOQUEAR se idade não está na faixa permitida
    if (_isAgeRestricted) {
      return false;
    }

    if (_isGenderRestricted) {
      return false;
    }

    return true;
  }
  
  bool get isAgeRestricted => _isAgeRestricted;
  String? get ageRestrictionMessage {
    if (_isAgeRestricted && _minAge != null && _maxAge != null) {
      return 'Indisponível para sua idade';
    }
    return null;
  }

  String get _genderRestrictionButtonTextKey {
    switch (_requiredGender) {
      case GENDER_WOMAN:
        return 'gender_restricted_female';
      case GENDER_MAN:
        return 'gender_restricted_male';
      case GENDER_TRANS:
        return 'gender_restricted_trans';
      case GENDER_OTHER:
        return 'gender_restricted_non_binary';
      default:
        return 'gender_restricted';
    }
  }

  // ---------------------------------------------------------------------------
  // REALTIME LISTENERS
  // ---------------------------------------------------------------------------

  void _setupRealtimeListeners() {
    if (_listenersInitialized) return;
    _listenersInitialized = true;

    _authSub ??= _auth.authStateChanges().listen((user) {
      if (user != null) return;
      _cancelRealtimeSubscriptions();
    });

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // LISTENER DA APPLICATION DO USUÁRIO
    _applicationSub = FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (_disposed) return;
      
      // 🔒 Se o usuário acabou de sair, ignorar re-hidratação tardia do stream
      // Isso previne o flash quando o snapshot ainda contém dados antigos
      if (_forceLeft) {
        debugPrint('🔒 [EventCard] Ignorando snapshot tardio - usuário já saiu do evento');
        return;
      }

      if (snapshot.docs.isEmpty) {
        _userApplication = null;
      } else {
        _userApplication = EventApplicationModel.fromFirestore(snapshot.docs.first);
      }

      notifyListeners();
    }, onError: _handleRealtimeStreamError);

    // LISTENER DO EVENTO (para detectar mudanças em minAge/maxAge)
    _eventSub = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .snapshots()
        .listen((doc) {
      if (_disposed) return;
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;

      _creatorId = data['createdBy'] ?? _creatorId;

      final participantsData = data['participants'] as Map<String, dynamic>?;
      if (participantsData != null) {
        _privacyType = participantsData['privacyType'] ?? _privacyType;
        
        // ✅ ATUALIZAR restrições de idade e revalidar
        final newMinAge = participantsData['minAge'] as int?;
        final newMaxAge = participantsData['maxAge'] as int?;
        
        if (newMinAge != _minAge || newMaxAge != _maxAge) {
          _minAge = newMinAge;
          _maxAge = newMaxAge;
          // ✅ APENAS revalidar se as restrições mudaram E não temos valor pré-carregado
          // Se já temos _isAgeRestricted do preload, manter até que realmente mude
          if (_userAge != null) {
            // Resetar para forçar nova verificação apenas se já havia validado antes
            _userAge = null;
            _isAgeRestricted = false;
          }
          // Revalidar idade assincronamente
          if (uid != null && !isCreator) {
            _validateUserAge(uid);
          }
        }
        
        // ✅ ATUALIZAR restrição de gênero
        final newGender = participantsData['gender'] as String?;
        if (newGender != _requiredGender) {
          _requiredGender = newGender;
          if (uid != null && !isCreator) {
            _validateUserGender(uid);
          }
        }
      }

      _emoji = data['emoji'] ?? _emoji;
      _activityText = data['activityText'] ?? _activityText;

      final loc = data['location'] as Map<String, dynamic>?;
      if (loc != null) {
        _locationName = loc['locationName'] ?? _locationName;
      }

      notifyListeners();
    }, onError: _handleRealtimeStreamError);
    
    // LISTENER DOS PARTICIPANTES APROVADOS
    // ✅ Escutar AMBOS 'approved' E 'autoApproved' para atualizar lista em tempo real
  _participantsSnapshotStream ??= FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('status', whereIn: ['approved', 'autoApproved'])
    .snapshots();

  // Primeiro evento do stream: não buscar do Firestore se já temos dados
  bool isFirstStreamEvent = true;

  _participantsSub = _participantsSnapshotStream!.listen((snapshot) async {
      // Guard duplo: antes e depois de operações async
      if (_disposed) return;
      
      final uid = _auth.currentUser?.uid;
      final snapshotCount = snapshot.docs.length;
      final localCount = _approvedParticipants.length;
      
      // ✅ PRIMEIRO EVENTO DO STREAM
      if (isFirstStreamEvent) {
        isFirstStreamEvent = false;
        
        // Se já temos participantes pré-carregados E a contagem bate, usar eles
        if (_approvedParticipants.isNotEmpty && (snapshotCount - localCount).abs() <= 1) {
          debugPrint('📱 [EventCard] Usando participantes pré-carregados (${_approvedParticipants.length})');
          return;
        }
        
        // Se NÃO temos participantes pré-carregados, buscar imediatamente
        if (_approvedParticipants.isEmpty && snapshotCount > 0) {
          debugPrint('📱 [EventCard] Buscando ${snapshotCount} participantes (sem pré-load)...');
          final userIds = snapshot.docs.map((doc) => doc.data()['userId'] as String).toList();
          
          try {
            final usersData = await _userRepo.getUsersBasicInfo(userIds);
            
            if (_disposed) return;
            
            _approvedParticipants = usersData.map((userData) => {
              'userId': userData['userId'],
              'photoUrl': userData['photoUrl'],
              'fullName': userData['fullName'],
            }).toList();
            
            _preloadParticipantAvatars();
            debugPrint('✅ [EventCard] Participantes carregados: ${_approvedParticipants.length}');
            unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
            notifyListeners();
          } catch (e) {
            debugPrint('⚠️ [EventCard] Erro ao buscar participantes: $e');
          }
          return;
        }
      }
      
      // ✅ PRESERVAR participante otimista durante transição
      // Se o usuário atual ainda não está no snapshot mas estava na lista local (otimista),
      // manter ele até que o servidor confirme
      final currentUserInSnapshot = uid != null && snapshot.docs.any((doc) => doc.data()['userId'] == uid);
      final currentUserInLocalList = uid != null && _approvedParticipants.any((p) => p['userId'] == uid);
      final isOptimisticUpdate = currentUserInLocalList && !currentUserInSnapshot;
      
      if (isOptimisticUpdate) {
        // Manter lista atual - o participante otimista ainda não chegou ao servidor
        debugPrint('📱 [EventCard] Mantendo participante otimista enquanto aguarda servidor');
        return;
      }
      
      // ✅ OTIMIZAÇÃO: Extrair userIds diretamente do snapshot (já temos!)
      // Evita query redundante ao EventApplications
      final snapshotUserIds = snapshot.docs
          .map((doc) => doc.data()['userId'] as String)
          .toList();
      
      // Verificar se realmente mudou (evita rebuilds desnecessários)
      final currentUserIds = _approvedParticipants.map((p) => p['userId'] as String).toSet();
      final newUserIds = snapshotUserIds.toSet();
      
      if (currentUserIds.length == newUserIds.length && 
          currentUserIds.containsAll(newUserIds)) {
        // Mesmos participantes, não precisa atualizar
        return;
      }
      
      debugPrint('📱 [EventCard] Participantes mudaram: ${currentUserIds.length} → ${newUserIds.length}');
      
      // ✅ Buscar dados dos usuários (avatares/nomes) - isso usa cache do UserRepository
      // Mas só busca os dados dos NOVOS usuários que ainda não temos
      final newUsers = newUserIds.difference(currentUserIds);
      final removedUsers = currentUserIds.difference(newUserIds);
      
      if (removedUsers.isNotEmpty) {
        // Alguém saiu: remover da lista local (instantâneo)
        _approvedParticipants = _approvedParticipants
            .where((p) => !removedUsers.contains(p['userId']))
            .toList();
        
        if (_disposed) return;
        unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
        notifyListeners();
      }
      
      if (newUsers.isNotEmpty) {
        // Alguém entrou: buscar dados do novo usuário
        try {
          final newUsersData = await _userRepo.getUsersBasicInfo(newUsers.toList());
          
          if (_disposed) return;
          
          // Adicionar novos participantes à lista
          for (final userData in newUsersData) {
            _approvedParticipants.add({
              'userId': userData['userId'],
              'photoUrl': userData['photoUrl'],
              'fullName': userData['fullName'],
            });
          }
          
          unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
          notifyListeners();
        } catch (e) {
          debugPrint('⚠️ [EventCard] Erro ao buscar dados de novos participantes: $e');
        }
      }
  }, onError: _handleRealtimeStreamError);
  }

  void _cancelRealtimeSubscriptions() {
    _applicationSub?.cancel();
    _applicationSub = null;
    _eventSub?.cancel();
    _eventSub = null;
    _participantsSub?.cancel();
    _participantsSub = null;
  }

  void _handleRealtimeStreamError(Object error) {
    final isPermissionDenied = error is FirebaseException && error.code == 'permission-denied';
    final isLoggedOut = _auth.currentUser == null;
    if (isPermissionDenied && isLoggedOut) {
      _cancelRealtimeSubscriptions();
      return;
    }

    debugPrint('❌ [EventCardController] Erro em stream realtime: $error');
  }

  // ---------------------------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    try {
      if (_preloadedEvent == null) {
        await _loadEventData();
      }

      if (_creatorFullName == null && _creatorId != null) {
        final userData = await _userRepo.getUserBasicInfo(_creatorId!);
        _creatorFullName = userData?['fullName'];
      }

      if (_userApplication == null) {
        await _loadUserApplication();
      }

      if (_preloadedEvent?.participants == null) {
        await _loadApprovedParticipants();
      }

      _loaded = true;

      _setupRealtimeListeners();

      notifyListeners();
    } catch (e) {
      _error = 'Erro ao carregar dados: $e';
      _loaded = false;
      notifyListeners();
    }
  }

  Future<void> _loadEventData() async {
    final eventData = await _eventRepo.getEventBasicInfo(eventId);
    if (eventData == null) throw Exception('Evento não encontrado');

    _creatorId = eventData['createdBy'];
    _locationName = eventData['locationName'];
    _emoji = eventData['emoji'];
    _activityText = eventData['activityText'];
    _scheduleDate = eventData['scheduleDate'];
    _privacyType = eventData['privacyType'];
    
    // ✅ CARREGAR restrições de idade
    final participants = eventData['participants'] as Map<String, dynamic>?;
    if (participants != null) {
      _minAge = participants['minAge'] as int?;
      _maxAge = participants['maxAge'] as int?;
    }
  }

  Future<void> _loadUserApplication() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _userApplication = await _applicationRepo.getUserApplication(
      eventId: eventId,
      userId: userId,
    );
  }

  Future<void> _loadApprovedParticipants() async {
    _approvedParticipants =
        await _applicationRepo.getApprovedApplicationsWithUserData(eventId);
    
    // Preload avatares para evitar "popping" na UI
    _preloadParticipantAvatars();
  }

  /// Preload dos avatares dos participantes para exibição instantânea
  void _preloadParticipantAvatars() {
    for (final p in _approvedParticipants) {
      final userId = p['userId'] as String?;
      final photoUrl = p['photoUrl'] as String?;
      if (userId != null && photoUrl != null && photoUrl.isNotEmpty) {
        UserStore.instance.preloadAvatar(userId, photoUrl);
      }
    }
  }

  /// Aguarda o download real dos avatares dos participantes
  /// 
  /// Use ANTES de exibir o EventCard para garantir que os avatares
  /// apareçam imediatamente, sem "popping".
  Future<void> preloadAvatarsAsync() async {
    final futures = <Future<void>>[];
    
    for (final p in _approvedParticipants) {
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
    final imageProvider = CachedNetworkImageProvider(url);
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

  // ---------------------------------------------------------------------------
  // APPLY
  // ---------------------------------------------------------------------------

  Future<void> applyToEvent() async {
    if (_isApplying || hasApplied || _privacyType == null) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    
    // ✅ VALIDAR idade antes de aplicar
    await _validateUserAge(uid);
    
    if (_isAgeRestricted) {
      _error = ageRestrictionMessage;
      notifyListeners();
      return;
    }

    // ✅ VALIDAR gênero antes de aplicar
    await _validateUserGender(uid);

    if (_isGenderRestricted) {
      notifyListeners();
      return;
    }

    _isApplying = true;
    notifyListeners();

    try {
      await _applicationRepo.createApplication(
        eventId: eventId,
        userId: uid,
        eventPrivacyType: _privacyType!,
      );
      
      // Stream do ParticipantsAvatarsList vai atualizar automaticamente
    } catch (e) {
      rethrow;
    } finally {
      _isApplying = false;
      notifyListeners();
    }
  }
  
  /// Valida se o usuário tem idade permitida para o evento
  Future<void> _validateUserAge(String userId) async {
    // ✅ Se já foi inicializado do preload COM valores de minAge/maxAge, usar o valor pré-calculado
    // (o valor já foi calculado no MapViewModel._enrichEvents)
    if (_preloadedEvent != null && _minAge != null && _maxAge != null) {
      // Já temos o valor pré-calculado, não precisa validar novamente
      // _isAgeRestricted já foi inicializado com o valor correto
      return;
    }
    
    // Se já validou manualmente ou é criador, não precisa validar novamente
    if (_userAge != null || isCreator) return;
    
    // Se não há restrições de idade definidas, permitir
    if (_minAge == null || _maxAge == null) {
      _isAgeRestricted = false;
      return;
    }
    
    try {
      // Buscar idade do usuário na coleção users
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (!userDoc.exists) {
        _isAgeRestricted = true;
        return;
      }
      
      final userData = userDoc.data();
      if (userData == null) {
        _isAgeRestricted = true;
        return;
      }
      
      // ✅ Obter idade como number (int) da raiz do documento
      final age = userData['age'];
      
      if (age == null) {
        _isAgeRestricted = true;
        return;
      }
      
      // Converter para int se vier como num
      _userAge = age is int ? age : (age as num).toInt();
      
      // ✅ VALIDAR se está na faixa permitida
      _isAgeRestricted = _userAge! < _minAge! || _userAge! > _maxAge!;
      
      debugPrint('🔒 [EventCard] Validação de idade: userAge=$_userAge, range=$_minAge-$_maxAge, restricted=$_isAgeRestricted');
    } catch (e) {
      debugPrint('❌ [EventCard] Erro ao validar idade: $e');
      _isAgeRestricted = true;
    }
  }

  /// Valida se o gênero do usuário é permitido
  Future<void> _validateUserGender(String userId) async {
    if (_requiredGender == null || _requiredGender == GENDER_ALL) {
      _isGenderRestricted = false;
      return;
    }

    if (isCreator) {
      _isGenderRestricted = false;
      return;
    }

    if (_currentUserGender != null) {
      _isGenderRestricted = _currentUserGender != _requiredGender;
      notifyListeners();
      return;
    }

    try {
      final userData = await _userRepo.getUserById(userId);
      
      if (userData == null) {
        _isGenderRestricted = true;
        notifyListeners();
        return;
      }

      _currentUserGender = userData['gender'] as String?;
      
      // Se não tem gênero definido no perfil, bloqueia se a atividade é restrita
      if (_currentUserGender == null) {
        _isGenderRestricted = true;
        notifyListeners();
        return;
      }

      _isGenderRestricted = _currentUserGender != _requiredGender;
      debugPrint('🔒 [EventCard] Validação de gênero: user=$_currentUserGender required=$_requiredGender blocked=$_isGenderRestricted');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [EventCard] Erro ao validar gênero: $e');
      _isGenderRestricted = true;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // LEAVE
  // ---------------------------------------------------------------------------

  Future<void> leaveEvent() async {
    debugPrint('🚪 EventCardController.leaveEvent iniciado');
    debugPrint('📋 EventId: $eventId');
    debugPrint('👤 Has Applied: $hasApplied');
    debugPrint('🔄 Is Leaving: $_isLeaving');
    
    if (!hasApplied) {
      debugPrint('❌ Usuário não aplicou para este evento');
      return;
    }
    
    if (_isLeaving) {
      debugPrint('⚠️ Já está saindo do evento');
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('❌ UID é nulo, usuário não autenticado');
      return;
    }
    
    debugPrint('👤 Current UID: $uid');

    _isLeaving = true;
    
    // 🔑 PONTO CRÍTICO: Atualizar estado local imediatamente para UX fluida
    // Isso garante que a UI reaja instantaneamente à intenção do usuário
    _forceLeft = true;
    _userApplication = null;
    
    notifyListeners();
    
    debugPrint('🔄 Chamando removeUserApplication...');

    try {
      await _applicationRepo.removeUserApplication(
        eventId: eventId,
        userId: uid,
      );
      debugPrint('✅ Aplicação removida com sucesso');
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao remover aplicação: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      rethrow;
    } finally {
      if (!_disposed) {
        _isLeaving = false;
        notifyListeners();
        debugPrint('🔄 Estado de saída resetado');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------

  Future<void> deleteEvent() async {
    debugPrint('🗑️ EventCardController.deleteEvent iniciado');
    debugPrint('📋 EventId: $eventId');
    debugPrint('👤 Is Creator: $isCreator');
    debugPrint('🔄 Is Deleting: $_isDeleting');
    
    if (!isCreator) {
      debugPrint('❌ Usuário não é o criador do evento');
      return;
    }
    
    if (_isDeleting) {
      debugPrint('⚠️ Já está deletando o evento');
      return;
    }

    _isDeleting = true;
    notifyListeners();
    
    debugPrint('🔄 Chamando EventDeletionService...');

    try {
      final deletionService = EventDeletionService();
      final success = await deletionService.deleteEvent(eventId);
      
      if (!success) {
        throw Exception('Falha ao deletar evento');
      }
      
      debugPrint('✅ Evento deletado com sucesso');
      
      // ✅ Remover marker do mapa instantaneamente
      MapViewModel.instance?.removeEvent(eventId);
      debugPrint('✅ Marker removido do mapa');
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao deletar evento: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      _error = 'Erro ao deletar evento: $e';
      rethrow;
    } finally {
      if (!_disposed) {
        _isDeleting = false;
        notifyListeners();
        debugPrint('🔄 Estado de deleção resetado');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // REFRESH
  // ---------------------------------------------------------------------------

  Future<void> refresh() async {
    _loaded = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _authSub = null;
    _cancelRealtimeSubscriptions();
    super.dispose();
  }
}
