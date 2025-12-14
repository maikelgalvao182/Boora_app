import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/utils/date_formatter.dart';

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

  // Participants
  List<Map<String, dynamic>> _approvedParticipants = [];
  
  // Age restriction
  int? _minAge;
  int? _maxAge;
  int? _userAge;
  bool _isAgeRestricted = false;

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

      if (_preloadedEvent!.participants != null) {
        _approvedParticipants = _preloadedEvent!.participants!;
      }

      if (_privacyType != null && _creatorId != null) {
        _loaded = true;
      }
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
  bool get hasData => _error == null && _creatorFullName != null && _locationName != null && _activityText != null;

  EventApplicationModel? get userApplication => _userApplication;
  bool get hasApplied => _userApplication != null;
  bool get isApproved => isCreator || (_userApplication?.isApproved ?? false);
  bool get isPending => _userApplication?.isPending ?? false;
  bool get isRejected => _userApplication?.isRejected ?? false;
  bool get isApplying => _isApplying;
  bool get isLeaving => _isLeaving;
  bool get isDeleting => _isDeleting;
  bool get isCreator => _auth.currentUser?.uid == _creatorId;

  List<Map<String, dynamic>> get approvedParticipants => _approvedParticipants;
  int get participantsCount => _approvedParticipants.length;
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

    return true;
  }
  
  bool get isAgeRestricted => _isAgeRestricted;
  String? get ageRestrictionMessage {
    if (_isAgeRestricted && _minAge != null && _maxAge != null) {
      return 'Indisponível para sua idade';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // REALTIME LISTENERS
  // ---------------------------------------------------------------------------

  void _setupRealtimeListeners() {
    if (_listenersInitialized) return;
    _listenersInitialized = true;

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

      if (snapshot.docs.isEmpty) {
        _userApplication = null;
      } else {
        _userApplication = EventApplicationModel.fromFirestore(snapshot.docs.first);
      }

      notifyListeners();
    });

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
      }

      _emoji = data['emoji'] ?? _emoji;
      _activityText = data['activityText'] ?? _activityText;

      final loc = data['location'] as Map<String, dynamic>?;
      if (loc != null) {
        _locationName = loc['locationName'] ?? _locationName;
      }

      notifyListeners();
    });
    
    // LISTENER DOS PARTICIPANTES APROVADOS
    _participantsSub = FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snapshot) async {
      if (_disposed) return;
      
      // Recarregar participantes com dados do usuário
      _approvedParticipants = await _applicationRepo.getApprovedApplicationsWithUserData(eventId);
      notifyListeners();
    });
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

    _isApplying = true;
    notifyListeners();

    try {
      await _applicationRepo.createApplication(
        eventId: eventId,
        userId: uid,
        eventPrivacyType: _privacyType!,
      );
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
    
    debugPrint('🔄 Iniciando deleção completa do evento...');

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      
      // 1. Buscar todos os participantes aprovados para remover suas conversas
      debugPrint('🔍 Buscando participantes do evento...');
      final applicationsSnapshot = await firestore
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .get();
      
      final participantIds = applicationsSnapshot.docs
          .map((doc) => doc.data()['userId'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      debugPrint('👥 ${participantIds.length} participantes encontrados');
      
      // 2. Deletar subcoleção Messages PRIMEIRO (antes de tudo)
      // As regras de Messages precisam que events/{eventId} ainda exista
      debugPrint('🔄 Deletando mensagens do chat...');
      final messagesSnapshot = await firestore
          .collection('EventChats')
          .doc(eventId)
          .collection('Messages')
          .get();
      
      for (final messageDoc in messagesSnapshot.docs) {
        await messageDoc.reference.delete();
      }
      debugPrint('✅ ${messagesSnapshot.docs.length} mensagens deletadas');
      
      // 3. Deletar documento principal do EventChats
      // Agora pode deletar porque Messages já foram removidas
      debugPrint('🔄 Tentando deletar EventChat document...');
      final eventChatRef = firestore.collection('EventChats').doc(eventId);
      await eventChatRef.delete();
      debugPrint('✅ EventChat deletado');
      
      // 4. Deletar conversas de todos os participantes
      debugPrint('🔄 Preparando deleção de ${participantIds.length} conversas no batch...');
      for (final participantId in participantIds) {
        final conversationRef = firestore
            .collection('Connections')
            .doc(participantId)
            .collection('Conversations')
            .doc('event_$eventId');
        
        // 🧪 Testar se pode ler antes de deletar
        try {
          final conversationDoc = await conversationRef.get();
          if (conversationDoc.exists) {
            debugPrint('   ✅ Conversa existe: Connections/$participantId/Conversations/event_$eventId');
          } else {
            debugPrint('   ⚠️ Conversa NÃO existe: Connections/$participantId/Conversations/event_$eventId');
          }
        } catch (e) {
          debugPrint('   ❌ Erro ao verificar conversa de $participantId: $e');
        }
        
        debugPrint('   📝 Adicionando ao batch: Connections/$participantId/Conversations/event_$eventId');
        batch.delete(conversationRef);
      }
      debugPrint('✅ ${participantIds.length} conversas adicionadas ao batch');
      
      // 5. Deletar todas as aplicações do evento
      debugPrint('🔄 Preparando deleção de ${applicationsSnapshot.docs.length} aplicações no batch...');
      for (final doc in applicationsSnapshot.docs) {
        debugPrint('   📝 Adicionando ao batch: EventApplications/${doc.id}');
        batch.delete(doc.reference);
      }
      debugPrint('✅ ${applicationsSnapshot.docs.length} aplicações adicionadas ao batch');
      
      // 6. Deletar documento do evento
      debugPrint('🔄 Preparando deleção do evento no batch...');
      final eventRef = firestore.collection('events').doc(eventId);
      debugPrint('   📝 Adicionando ao batch: events/$eventId');
      batch.delete(eventRef);
      debugPrint('✅ Evento adicionado ao batch');
      
      // Executar batch
      debugPrint('🔥 Executando batch com ${participantIds.length + applicationsSnapshot.docs.length + 1} operações...');
      debugPrint('   - ${participantIds.length} conversas');
      debugPrint('   - ${applicationsSnapshot.docs.length} aplicações');
      debugPrint('   - 1 evento');
      await batch.commit();
      debugPrint('✅ Batch executado com sucesso');
      
      debugPrint('✅ Evento e todos os dados relacionados deletados com sucesso');
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
    _applicationSub?.cancel();
    _eventSub?.cancel();
    _participantsSub?.cancel();
    super.dispose();
  }
}
