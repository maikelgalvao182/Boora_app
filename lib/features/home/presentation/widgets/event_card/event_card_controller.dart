import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/cache/app_cache_service.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/services/event_card_action_warmup_service.dart';
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
  final MapViewModel? _mapViewModel; // Injected dependency
  final String eventId;
  final EventModel? _preloadedEvent;
  final EventCardActionWarmupState? _warmupState;
  final bool _enableRealtime;
  final bool _enableOpenFetches;
  final bool _enableReactiveCreatorName;

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
  Future<void>? _loadFuture;

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
  
  // 🎯 Controle de inicialização dos participantes (evita "pop" ao abrir card)
  bool _participantsInitialized = false;
  Future<void>? _participantsHydrationFuture;
  Completer<void>? _participantsReadyCompleter;
  
  // Age restriction
  int? _minAge;
  int? _maxAge;
  int? _userAge;
  bool _isAgeRestricted = false;

  // Gender restriction
  String? _requiredGender;
  String? _currentUserGender;
  bool _isGenderRestricted = false;

  // VIP status (allows events beyond 30km)
  bool _isUserVip = false;
  bool _vipStatusChecked = false;

  EventCardController({
    required this.eventId,
    EventModel? preloadedEvent,
    FirebaseAuth? auth,
    EventApplicationRepository? applicationRepo,
    EventRepository? eventRepo,
    UserRepository? userRepo,
    MapViewModel? mapViewModel,
    EventCardActionWarmupState? warmupState,
    bool enableRealtime = true,
    bool enableOpenFetches = true,
    bool enableReactiveCreatorName = true,
  })  : _preloadedEvent = preloadedEvent,
        _auth = auth ?? FirebaseAuth.instance,
        _applicationRepo = applicationRepo ?? EventApplicationRepository(),
        _eventRepo = eventRepo ?? EventRepository(),
        _userRepo = userRepo ?? UserRepository(),
        _mapViewModel = mapViewModel,
      _warmupState = warmupState,
        _enableRealtime = enableRealtime,
        _enableOpenFetches = enableOpenFetches,
        _enableReactiveCreatorName = enableReactiveCreatorName {
    debugPrint('🎫 [EventCardController] injected mapVM hash=${_mapViewModel != null ? identityHashCode(_mapViewModel) : 'NULL'}');
    debugPrint('🎫 [EventCardController] singleton mapVM hash=${identityHashCode(MapViewModel.instance)}');
    _initializeFromPreload();
    // ✅ Iniciar listeners imediatamente para garantir reatividade dos botões
    if (_enableRealtime) {
      _setupRealtimeListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // INITIALIZAÇÃO COM PRELOADED EVENT
  // ---------------------------------------------------------------------------

  void _initializeFromPreload() {
    debugPrint('🎫 [EventCard] _initializeFromPreload - eventId: $eventId');
    debugPrint('🎫 [EventCard] _preloadedEvent: ${_preloadedEvent != null ? "EXISTS" : "NULL"}');

    _applyWarmupState();
    
    if (_preloadedEvent != null) {
      _emoji = _preloadedEvent!.emoji;
      _activityText = _preloadedEvent!.title;
      _locationName = _preloadedEvent!.locationName;
      _creatorFullName = _preloadedEvent!.creatorFullName;
      _scheduleDate = _preloadedEvent!.scheduleDate;
      _privacyType = _preloadedEvent!.privacyType;
      _creatorId = _preloadedEvent!.createdBy;

      // ✅ Preload avatar do criador no UserStore
      // events_card_preview não tem creatorPhotoUrl,
      // então resolvemos via Users/{creatorId} (one-time fetch)
      if (_creatorId != null && _creatorId!.isNotEmpty) {
        final creatorAvatar = _preloadedEvent!.creatorAvatarUrl;
        if (creatorAvatar != null && creatorAvatar.isNotEmpty) {
          UserStore.instance.preloadAvatar(_creatorId!, creatorAvatar);
        } else {
          UserStore.instance.resolveUser(_creatorId!);
        }
      }

      if (_preloadedEvent!.userApplication != null) {
        _userApplication = _preloadedEvent!.userApplication;
      }
      
      // ✅ INICIALIZAR isAgeRestricted E minAge/maxAge a partir do evento pré-carregado
      _isAgeRestricted = _preloadedEvent!.isAgeRestricted;
      _minAge = _preloadedEvent!.minAge;
      _maxAge = _preloadedEvent!.maxAge;

      // ✅ INICIALIZAR restrição de gênero
      _requiredGender = _preloadedEvent!.gender;
      // Se tiver restrição, validar o usuário
      if (_enableOpenFetches && _requiredGender != null && _requiredGender != GENDER_ALL) {
        _validateUserGender(_auth.currentUser?.uid ?? '');
      }

      // 👑 INICIALIZAR status VIP para permitir eventos além de 30km
      // NOTA: Esta verificação é redundante se o MapViewModel já enriqueceu o isAvailable
      // considerando o status VIP. Mas mantemos como fallback para casos onde o evento
      // não passou pelo enriquecimento do MapViewModel.
      if (_enableOpenFetches && !_preloadedEvent!.isAvailable) {
        final currentUserId = _auth.currentUser?.uid;
        if (currentUserId != null && currentUserId.isNotEmpty) {
          _checkUserVipStatus(currentUserId);
        }
      }

      if (_preloadedEvent!.participants != null) {
        _approvedParticipants = _preloadedEvent!.participants!;
        // Preload avatares para evitar "popping" na UI
        _preloadParticipantAvatars();
        _markParticipantsReady();
      } else {
        // ✅ Se não há participantes no preload, tentar cache (memória + Hive)
        // Iniciamos a hidratação mas guardamos o Future para poder awaitar depois
        _participantsHydrationFuture = _hydrateParticipantsFromCache();
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
        if (_enableOpenFetches && _creatorFullName == null && _creatorId != null) {
          _fetchCreatorNameInBackground();
        }
      } else {
        debugPrint('🎫 [EventCard] ⚠️ _loaded = false (privacyType ou creatorId é null)');
      }
    } else {
      debugPrint('🎫 [EventCard] ❌ _preloadedEvent é NULL - sem dados para carregar');
    }
  }

  void _applyWarmupState() {
    final warmupState = _warmupState;
    if (warmupState == null) return;

    if (_userApplication == null && warmupState.userApplication != null) {
      _userApplication = warmupState.userApplication;
    }

    if (warmupState.currentUserGender != null) {
      _currentUserGender = warmupState.currentUserGender;
    }

    if (warmupState.isGenderRestricted != null) {
      _isGenderRestricted = warmupState.isGenderRestricted!;
    }

    if (warmupState.userAge != null) {
      _userAge = warmupState.userAge;
    }

    if (warmupState.isAgeRestricted != null) {
      _isAgeRestricted = warmupState.isAgeRestricted!;
    }

    if (warmupState.isUserVip != null) {
      _isUserVip = warmupState.isUserVip!;
      _vipStatusChecked = true;
    }
  }

  /// Busca participantes do cache (memória + Hive) sem bloquear a UI
  /// Se cache vazio e realtime desabilitado, faz fetch direto do Firestore
  Future<void> _hydrateParticipantsFromCache() async {
    if (_disposed) return;

    try {
      final cached = await _applicationRepo.getCachedApprovedParticipants(eventId);
      if (_disposed) return;

      bool participantsLoaded = false;
      
      if (cached != null && cached.isNotEmpty) {
        if (_approvedParticipants.isEmpty) {
          _approvedParticipants = cached;
          _preloadParticipantAvatars();
          debugPrint('✅ [EventCard] Participantes carregados do cache (${cached.length})');
          participantsLoaded = true;
        }
      }
      
      // ✅ Se realtime desabilitado, buscar dados que faltam
      if (!_enableRealtime) {
        // Buscar participantes do Firestore se não veio do cache
        if (!participantsLoaded && _approvedParticipants.isEmpty) {
          await _fetchParticipantsOnce();
        }
        // ✅ SEMPRE buscar userApplication se não vier no preload
        await _fetchUserApplicationOnce();
      }
      
      _participantsInitialized = true;
      _markParticipantsReady();
      
      if (participantsLoaded) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ [EventCard] Erro ao hidratar participantes do cache: $e');
      _participantsInitialized = true; // Marcar como inicializado mesmo com erro
      _markParticipantsReady();
    }
  }
  
  /// Busca a aplicação do usuário atual uma única vez (sem stream)
  /// Usado quando enableRealtime = false e userApplication não veio no preload
  Future<void> _fetchUserApplicationOnce() async {
    if (_disposed) return;
    if (_userApplication != null) return; // Já tem
    
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    
    // Criador do evento não precisa de application
    if (uid == _creatorId) return;
    
    try {
      debugPrint('🔄 [EventCard] Buscando userApplication (one-shot fetch)...');
      final application = await _applicationRepo.getUserApplication(
        eventId: eventId,
        userId: uid,
      );
      
      if (_disposed) return;
      
      _userApplication = application;
      
      if (application != null) {
        debugPrint('✅ [EventCard] userApplication carregado: status=${application.status}');
      } else {
        debugPrint('📭 [EventCard] Usuário não tem application para este evento');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [EventCard] Erro ao buscar userApplication: $e');
    }
  }
  
  /// Busca participantes uma única vez do Firestore (sem stream)
  /// Usado quando enableRealtime = false e não há cache
  Future<void> _fetchParticipantsOnce() async {
    if (_disposed || _approvedParticipants.isNotEmpty) return;
    
    try {
      debugPrint('🔄 [EventCard] Buscando participantes (one-shot fetch)...');
      final participants = await _applicationRepo.getApprovedApplicationsWithUserData(eventId);
      
      if (_disposed) return;
      if (participants.isEmpty) {
        debugPrint('📭 [EventCard] Nenhum participante encontrado');
        return;
      }
      
      _approvedParticipants = participants.map((p) => {
        'userId': p['userId'],
        'photoUrl': p['photoUrl'],
        'fullName': p['fullName'],
        'isCreator': p['userId'] == _creatorId,
      }).toList();
      
      _preloadParticipantAvatars();
      debugPrint('✅ [EventCard] Participantes carregados via fetch (${_approvedParticipants.length})');
      
      // Cachear para próximas aberturas
      unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [EventCard] Erro ao buscar participantes: $e');
    }
  }
  
  /// Adiciona o usuário atual à lista de participantes localmente
  /// Usado após join bem-sucedido para atualizar UI sem depender de streams
  Future<void> _addCurrentUserToParticipants(String uid) async {
    if (_disposed) return;
    
    // Verificar se já está na lista
    final alreadyExists = _approvedParticipants.any((p) => p['userId'] == uid);
    if (alreadyExists) {
      debugPrint('⚠️ [EventCard] Usuário já está na lista de participantes');
      return;
    }
    
    try {
      // Buscar dados do usuário para adicionar à lista
      final userData = await _userRepo.getUserBasicInfo(uid);
      if (_disposed) return;
      
      final newParticipant = {
        'userId': uid,
        'photoUrl': userData?['photoUrl'] as String?,
        'fullName': userData?['fullName'] as String?,
        'isCreator': false,
      };
      
      _approvedParticipants = [..._approvedParticipants, newParticipant];
      
      // Preload do avatar do novo participante
      final photoUrl = newParticipant['photoUrl'] as String?;
      if (photoUrl != null && photoUrl.isNotEmpty) {
        UserStore.instance.preloadAvatar(uid, photoUrl);
      }
      
      // Atualizar cache para manter consistência
      unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
      
      debugPrint('✅ [EventCard] Usuário adicionado à lista de participantes (total: ${_approvedParticipants.length})');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [EventCard] Erro ao adicionar usuário à lista: $e');
      // Não falha silenciosamente - streams/realtime eventualmente sincronizarão
    }
  }
  
  /// Remove o usuário atual da lista de participantes localmente
  /// Usado após leave bem-sucedido para atualizar UI sem depender de streams
  void _removeCurrentUserFromParticipants(String uid) {
    if (_disposed) return;
    
    final previousCount = _approvedParticipants.length;
    _approvedParticipants = _approvedParticipants
        .where((p) => p['userId'] != uid)
        .toList();
    
    if (_approvedParticipants.length < previousCount) {
      debugPrint('✅ [EventCard] Usuário removido da lista de participantes (total: ${_approvedParticipants.length})');
      
      // Atualizar cache para manter consistência
      unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
      
      notifyListeners();
    } else {
      debugPrint('⚠️ [EventCard] Usuário não estava na lista de participantes');
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
  bool get enableReactiveCreatorName => _enableReactiveCreatorName;

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
  bool get participantsReady => _participantsInitialized;
  
  /// 🎯 Aguarda até que os participantes estejam carregados E avatares baixados
  /// Chamar ANTES de abrir o EventCard para evitar "pop" dos avatares
  Future<void> ensureParticipantsLoaded() async {
    if (_participantsInitialized) {
      // Já carregou dados, mas precisa garantir que imagens foram baixadas
      await preloadAvatarsAsync();
      return;
    }
    _participantsReadyCompleter ??= Completer<void>();
    if (_participantsHydrationFuture != null) {
      await _participantsHydrationFuture;
    }
    if (!_participantsInitialized && _participantsReadyCompleter != null) {
      await _participantsReadyCompleter!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
    // Forçar download real das imagens após os dados estarem prontos
    await preloadAvatarsAsync();
  }
  
  Stream<int> get participantsCountStream => (_participantsSnapshotStream ??
    FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('status', whereIn: ['approved', 'autoApproved'])
        .limit(50) // Limite para reduzir leituras Firestore
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

    // 👑 Se evento não está disponível e usuário NÃO é VIP:
    // Mostrar botão ATIVO "Desbloquear acesso" que abre VipDialog
    if (isOutsideAreaNonVip) {
      return 'unlock_vip_access';
    }
    // Se é VIP, continua para verificações normais abaixo
    
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
    debugPrint('🔘 [EventCard] isButtonEnabled check:');
    debugPrint('   - isCreator: $isCreator');
    debugPrint('   - isApplying: $isApplying, isLeaving: $isLeaving, isDeleting: $isDeleting');
    debugPrint('   - isApproved: $isApproved');
    debugPrint('   - isPending: $isPending, isRejected: $isRejected');
    debugPrint('   - isAvailable: ${_preloadedEvent?.isAvailable}');
    debugPrint('   - _isUserVip: $_isUserVip');
    debugPrint('   - _isAgeRestricted: $_isAgeRestricted');
    debugPrint('   - _isGenderRestricted: $_isGenderRestricted');

    if (!_loaded || _privacyType == null) {
      debugPrint('⏳ [EventCard] Estado ainda carregando - botão desabilitado');
      return false;
    }
    
    if (isCreator) return true;
    if (isApplying || isLeaving || isDeleting) return false;
    if (isApproved) return true;
    if (isPending || isRejected) return false;

    // 👑 NOVO FLUXO: Se fora da área e NÃO é VIP, manter botão ATIVO
    // Ao clicar, abrirá VipDialog para conversão
    if (isOutsideAreaNonVip) {
      debugPrint('💎 [EventCard] Fora da área + não-VIP - botão ATIVO para abrir VipDialog');
      return true;
    }
    
    // 👑 Se usuário é VIP, permitir aplicar mesmo em eventos fora do raio de 30km
    if (_preloadedEvent != null && !_preloadedEvent!.isAvailable) {
      if (_isUserVip) {
        debugPrint('👑 [EventCard] Usuário VIP - permitindo evento fora do raio de 30km');
        return true;
      }
    }
    
    // ✅ BLOQUEAR se idade não está na faixa permitida
    if (_isAgeRestricted) {
      debugPrint('🔒 [EventCard] Idade restrita - bloqueando');
      return false;
    }

    if (_isGenderRestricted) {
      debugPrint('🔒 [EventCard] Gênero restrito - bloqueando');
      return false;
    }

    debugPrint('✅ [EventCard] Botão habilitado');
    return true;
  }
  
  bool get isAgeRestricted => _isAgeRestricted;
  String? get ageRestrictionMessage {
    if (_isAgeRestricted && _minAge != null && _maxAge != null) {
      return 'Indisponível para sua idade';
    }
    return null;
  }

  bool get isUserVip => _isUserVip;
  
  /// Verifica se evento está fora da área e usuário não é VIP
  /// Neste caso, mostramos botão ATIVO para abrir VipDialog
  bool get isOutsideAreaNonVip {
    if (_preloadedEvent == null) return false;
    return !_preloadedEvent!.isAvailable && !_isUserVip;
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
      if (user == null) {
        _cancelRealtimeSubscriptions();
        return;
      }
      
      // 👑 Verificar status VIP quando usuário faz login
      if (!_vipStatusChecked && user.uid.isNotEmpty) {
        _checkUserVipStatus(user.uid);
      }
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
      
      // ✅ TRATAMENTO DE DELEÇÃO REMOTA
      if (!doc.exists) {
        debugPrint('🗑️ [EventCard] Evento deletado remotamente detectado via stream');
        _error = 'Este evento foi cancelado ou removido.';
        _loaded = false;
        notifyListeners();
        
        // Remover do mapa imediatamente se a dependência estiver injetada
        _mapViewModel?.removeEvent(eventId);
        return;
      }

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
    .limit(50) // Limite para reduzir leituras Firestore
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
          _markParticipantsReady();
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
            _markParticipantsReady();
            debugPrint('✅ [EventCard] Participantes carregados: ${_approvedParticipants.length}');
            unawaited(_applicationRepo.cacheApprovedParticipants(eventId, _approvedParticipants));
            notifyListeners();
          } catch (e) {
            debugPrint('⚠️ [EventCard] Erro ao buscar participantes: $e');
          }
          return;
        }

        if (snapshotCount == 0) {
          _markParticipantsReady();
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

      if (_enableRealtime) {
        _setupRealtimeListeners();
      }

      notifyListeners();
    } catch (e) {
      _error = 'Erro ao carregar dados: $e';
      _loaded = false;
      notifyListeners();
    }
  }

  Future<void> ensureEventDataLoaded() async {
    if (_loaded) return;
    _loadFuture ??= load();

    try {
      await _loadFuture;
    } finally {
      if (_loaded || _error != null) {
        _loadFuture = null;
      }
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
    _markParticipantsReady();
  }

  void _markParticipantsReady() {
    _participantsInitialized = true;
    _participantsReadyCompleter ??= Completer<void>();
    if (!_participantsReadyCompleter!.isCompleted) {
      _participantsReadyCompleter!.complete();
    }
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

  // ---------------------------------------------------------------------------
  // APPLY
  // ---------------------------------------------------------------------------

  Future<void> applyToEvent() async {
    debugPrint('🎯 [EventCard] applyToEvent() INICIADO');
    debugPrint('   - _isApplying: $_isApplying');
    debugPrint('   - hasApplied: $hasApplied');
    debugPrint('   - _privacyType: $_privacyType');
    
    if (_isApplying || hasApplied || _privacyType == null) {
      debugPrint('⚠️ [EventCard] applyToEvent() BLOQUEADO - returnando');
      return;
    }

    final uid = _auth.currentUser?.uid;
    debugPrint('   - userId: $uid');
    if (uid == null) {
      debugPrint('❌ [EventCard] userId é null - returnando');
      return;
    }
    
    debugPrint('🔍 [EventCard] Validando idade...');
    // ✅ VALIDAR idade antes de aplicar
    await _validateUserAge(uid);
    
    if (_isAgeRestricted) {
      debugPrint('❌ [EventCard] Idade restrita - abortando');
      _error = ageRestrictionMessage;
      notifyListeners();
      return;
    }
    debugPrint('✅ [EventCard] Idade validada');

    debugPrint('🔍 [EventCard] Validando gênero...');
    // ✅ VALIDAR gênero antes de aplicar
    await _validateUserGender(uid);

    if (_isGenderRestricted) {
      debugPrint('❌ [EventCard] Gênero restrito - abortando');
      notifyListeners();
      return;
    }
    debugPrint('✅ [EventCard] Gênero validado');

    _isApplying = true;
    debugPrint('🔄 [EventCard] _isApplying = true, notificando listeners');
    notifyListeners();

    try {
      debugPrint('📝 [EventCard] Chamando _applicationRepo.createApplication...');
      await _applicationRepo.createApplication(
        eventId: eventId,
        userId: uid,
        eventPrivacyType: _privacyType!,
      );
      debugPrint('✅ [EventCard] createApplication completou com sucesso');
      
      // ✅ Atualizar userApplication localmente para refletir o novo estado
      // Isso garante que a UI mostre corretamente "Pendente" ou "Sair"
      final now = DateTime.now();
      final isAutoApproved = _privacyType == 'open';
      debugPrint('🔍 [EventCard] isAutoApproved: $isAutoApproved');
      
      _userApplication = EventApplicationModel(
        id: '', // ID será preenchido pelo stream/fetch posterior
        eventId: eventId,
        userId: uid,
        status: isAutoApproved 
            ? ApplicationStatus.autoApproved 
            : ApplicationStatus.pending,
        appliedAt: now,
        decisionAt: isAutoApproved ? now : null,
        presence: PresenceStatus.going,
      );
      debugPrint('✅ [EventCard] _userApplication atualizado localmente');
      
      // ✅ Se evento é open (autoApproved), adicionar usuário à lista local imediatamente
      // Isso garante que a UI reflita a mudança sem depender de streams/realtime
      if (isAutoApproved) {
        debugPrint('🔄 [EventCard] Adicionando usuário aos participantes locais...');
        await _addCurrentUserToParticipants(uid);
        debugPrint('✅ [EventCard] Usuário adicionado aos participantes');
      }
      
      debugPrint('✅ [EventCard] applyToEvent() COMPLETO COM SUCESSO');
      // Stream do ParticipantsAvatarsList vai atualizar automaticamente (se enableRealtime)
    } catch (e) {
      debugPrint('❌ [EventCard] ERRO em applyToEvent: $e');
      debugPrint('   Stack trace: ${StackTrace.current}');
      rethrow;
    } finally {
      _isApplying = false;
      if (!_disposed) {
        debugPrint('🔄 [EventCard] _isApplying = false, notificando listeners');
        notifyListeners();
      }
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

  /// Verifica se o usuário tem status VIP em users_preview
  /// Permite que usuários VIP apliquem em eventos além de 30km
  Future<void> _checkUserVipStatus(String userId) async {
    debugPrint('👑 [EventCard] _checkUserVipStatus CHAMADO para userId: $userId');
    debugPrint('👑 [EventCard] _vipStatusChecked antes: $_vipStatusChecked');
    
    if (_vipStatusChecked) {
      debugPrint('👑 [EventCard] VIP já verificado anteriormente - ignorando');
      return;
    }
    
    try {
      debugPrint('👑 [EventCard] Buscando users_preview/$userId...');
      final userPreviewDoc = await FirebaseFirestore.instance
          .collection('users_preview')
          .doc(userId)
          .get();

      debugPrint('👑 [EventCard] Documento existe: ${userPreviewDoc.exists}');

      if (!userPreviewDoc.exists) {
        debugPrint('⚠️ [EventCard] users_preview não encontrado para userId: $userId');
        _isUserVip = false;
        _vipStatusChecked = true;
        return;
      }

      final data = userPreviewDoc.data();
      debugPrint('👑 [EventCard] Dados do documento: $data');
      
      if (data == null) {
        debugPrint('⚠️ [EventCard] data é null');
        _isUserVip = false;
        _vipStatusChecked = true;
        return;
      }

      // Verificar user_is_vip (compatível com múltiplos formatos)
      dynamic rawVip = data['IsVip'] ?? data['user_is_vip'] ?? data['isVip'] ?? data['vip'];
      
      debugPrint('👑 [EventCard] rawVip encontrado: $rawVip (type: ${rawVip.runtimeType})');
      
      if (rawVip is bool) {
        _isUserVip = rawVip;
      } else if (rawVip is String) {
        _isUserVip = rawVip.toLowerCase() == 'true';
      } else {
        _isUserVip = false;
      }

      _vipStatusChecked = true;
      
      debugPrint('👑 [EventCard] Status VIP verificado: $_isUserVip para userId: $userId');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [EventCard] Erro ao verificar status VIP: $e');
      _isUserVip = false;
      _vipStatusChecked = true;
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

      // ✅ Remover referência da conversa em Connections para parar pushs e limpar lista de chats
      // Connections/{uid}/Conversations/event_{eventId}
      try {
        await FirebaseFirestore.instance
            .collection('Connections')
            .doc(uid)
            .collection('Conversations')
            .doc('event_$eventId')
            .delete();
        debugPrint('✅ Referência da conversa removida (Connections/Conversations)');
      } catch (e) {
        debugPrint('⚠️ Erro ao remover referência da conversa (não bloqueante): $e');
      }
      
      // ✅ Remover usuário da lista de participantes local imediatamente
      // Isso garante que a UI reflita a mudança sem depender de streams/realtime
      _removeCurrentUserFromParticipants(uid);

      // 🗑️ Invalidar AMBOS os caches (memória + Hive) para forçar fetch fresco
      // Evita que o Hive sirva lista antiga quando o memory cache expirar
      await _applicationRepo.invalidateParticipantsCache(eventId);
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao remover aplicação: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      // ⚠️ Reverter estado local se falhar
      _forceLeft = false;
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
      final mapVM = _mapViewModel;
      if (mapVM == null) {
        debugPrint('❌ [EventCardController] mapViewModel não injetado. Não consigo remover marker local.');
        return;
      }
      mapVM.removeEvent(eventId);
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
