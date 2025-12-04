import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// Controller para gerenciar dados do EventCard
class EventCardController extends ChangeNotifier {
  final FirebaseAuth _auth;
  final EventApplicationRepository _applicationRepo;
  final EventRepository _eventRepo;
  final UserRepository _userRepo;
  final String eventId;

  String? _creatorFullName;
  String? _locationName;
  String? _emoji;
  String? _activityText;
  DateTime? _scheduleDate;
  String? _privacyType;
  String? _creatorId;
  bool _loaded = false;
  String? _error;
  
  // Application state
  EventApplicationModel? _userApplication;
  bool _isApplying = false;

  // Participants data (approved applications with user info)
  List<Map<String, dynamic>> _approvedParticipants = [];

  EventCardController({
    required this.eventId,
    FirebaseAuth? auth,
    EventApplicationRepository? applicationRepo,
    EventRepository? eventRepo,
    UserRepository? userRepo,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _applicationRepo = applicationRepo ?? EventApplicationRepository(),
        _eventRepo = eventRepo ?? EventRepository(),
        _userRepo = userRepo ?? UserRepository();

  // Getters
  String? get creatorFullName => _creatorFullName;
  String? get locationName => _locationName;
  String? get emoji => _emoji;
  String? get activityText => _activityText;
  DateTime? get scheduleDate => _scheduleDate;
  String? get privacyType => _privacyType;
  String? get creatorId => _creatorId;
  bool get isLoading => !_loaded && _error == null;
  String? get error => _error;
  bool get hasData => _loaded && _error == null && _creatorFullName != null && _locationName != null && _activityText != null;
  
  // Application getters
  EventApplicationModel? get userApplication => _userApplication;
  bool get hasApplied => _userApplication != null;
  bool get isApproved => _userApplication?.isApproved ?? false;
  bool get isPending => _userApplication?.isPending ?? false;
  bool get isRejected => _userApplication?.isRejected ?? false;
  bool get isApplying => _isApplying;
  bool get isCreator => _auth.currentUser?.uid == _creatorId;
  
  // Participants
  List<Map<String, dynamic>> get approvedParticipants => _approvedParticipants;
  int get participantsCount => _approvedParticipants.length;
  
  /// Texto do botão baseado no estado
  String get buttonText {
    if (isCreator) return 'view_participants';
    if (isApplying) return 'applying';
    if (isApproved) return 'view_event_chat';
    if (isPending) return 'awaiting_approval';
    if (isRejected) return 'application_rejected';
    return privacyType == 'open' ? 'participate' : 'request_participation';
  }
  
  /// Se o botão deve estar habilitado
  bool get isButtonEnabled {
    if (isCreator) return true;
    if (isApplying) return false;
    if (isApproved) return true;
    if (isPending || isRejected) return false;
    return true; // Pode aplicar
  }

  /// Carrega dados do evento de forma assíncrona (ANTES de abrir o widget)
  Future<void> load() async {
    try {
      await _loadEventData();
      await _loadUserApplication();
      await _loadApprovedParticipants();
      _loaded = true;
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao carregar dados: $e';
      _loaded = false;
      notifyListeners();
    }
  }

  /// Carrega dados do evento e do criador usando repositories
  Future<void> _loadEventData() async {
    // Buscar dados básicos do evento
    final eventData = await _eventRepo.getEventBasicInfo(eventId);

    if (eventData == null) {
      throw Exception('Evento não encontrado');
    }

    // Extrair campos já parseados
    _creatorId = eventData['createdBy'] as String?;
    _locationName = eventData['locationName'] as String?;
    _emoji = eventData['emoji'] as String?;
    _activityText = eventData['activityText'] as String?;
    _scheduleDate = eventData['scheduleDate'] as DateTime?;
    _privacyType = eventData['privacyType'] as String?;

    // Buscar dados do criador
    if (_creatorId != null) {
      final userData = await _userRepo.getUserBasicInfo(_creatorId!);
      _creatorFullName = userData?['fullName'] as String?;
    }
  }
  /// Carrega aplicação do usuário atual (se existir)
  Future<void> _loadUserApplication() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    
    _userApplication = await _applicationRepo.getUserApplication(
      eventId: eventId,
      userId: userId,
    );
  }
  
  /// Carrega lista de participantes aprovados com dados dos usuários
  Future<void> _loadApprovedParticipants() async {
    _approvedParticipants = await _applicationRepo.getApprovedApplicationsWithUserData(eventId);
    debugPrint('✅ Carregados ${_approvedParticipants.length} participantes aprovados');
  }
  
  /// Aplica para participar do evento
  Future<void> applyToEvent() async {
    if (_isApplying || hasApplied || _privacyType == null) return;
    
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Usuário não autenticado');
    
    try {
      _isApplying = true;
      notifyListeners();
      
      final applicationId = await _applicationRepo.createApplication(
        eventId: eventId,
        userId: userId,
        eventPrivacyType: _privacyType!,
      );
      
      // Recarregar aplicação
      await _loadUserApplication();
      
      debugPrint('✅ Aplicação criada com sucesso: $applicationId');
    } catch (e) {
      debugPrint('❌ Erro ao aplicar: $e');
      rethrow;
    } finally {
      _isApplying = false;
      notifyListeners();
    }
  }

  /// Recarrega os dados
  Future<void> refresh() async {
    _loaded = false;
    _error = null;
    notifyListeners();
    await load();
  }
}

