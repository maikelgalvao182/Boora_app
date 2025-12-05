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
  final EventModel? _preloadedEvent; // Evento pré-carregado (opcional)

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
    debugPrint('🏗️ EventCardController construtor iniciado');
    debugPrint('   - eventId: $eventId');
    debugPrint('   - preloadedEvent: ${preloadedEvent != null ? "SIM" : "NÃO"}');
    
    if (_preloadedEvent != null) {
      debugPrint('📦 Usando dados pré-carregados:');
      debugPrint('   - emoji: ${_preloadedEvent!.emoji}');
      debugPrint('   - title: ${_preloadedEvent!.title}');
      debugPrint('   - locationName: ${_preloadedEvent!.locationName}');
      debugPrint('   - creatorFullName: ${_preloadedEvent!.creatorFullName}');
      debugPrint('   - privacyType: ${_preloadedEvent!.privacyType}');
      debugPrint('   - createdBy: ${_preloadedEvent!.createdBy}');
      debugPrint('   - userApplication: ${_preloadedEvent!.userApplication != null ? "SIM (${_preloadedEvent!.userApplication!.status.value})" : "NÃO"}');
      
      _emoji = _preloadedEvent!.emoji;
      _activityText = _preloadedEvent!.title;
      _locationName = _preloadedEvent!.locationName;
      _creatorFullName = _preloadedEvent!.creatorFullName;
      _scheduleDate = _preloadedEvent!.scheduleDate;
      _privacyType = _preloadedEvent!.privacyType;
      _creatorId = _preloadedEvent!.createdBy;
      
      // PRÉ-CARREGA aplicação do usuário se vier no EventModel
      _userApplication = _preloadedEvent!.userApplication;
      
      if (_preloadedEvent!.participants != null) {
        _approvedParticipants = _preloadedEvent!.participants!;
      }
      
      debugPrint('✅ Dados do controller após construtor:');
      debugPrint('   - _privacyType: $_privacyType');
      debugPrint('   - _creatorId: $_creatorId');
      debugPrint('   - _userApplication: ${_userApplication != null ? "SIM (${_userApplication!.status.value})" : "NÃO"}');
    } else {
      debugPrint('⚠️ Nenhum evento pré-carregado, será necessário buscar do Firestore');
    }
  }

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
  bool get hasData => _error == null && _creatorFullName != null && _locationName != null && _activityText != null;
  
  // Application getters
  EventApplicationModel? get userApplication => _userApplication;
  bool get hasApplied => _userApplication != null;
  /// Owner sempre é considerado aprovado, mesmo sem application carregada
  bool get isApproved => isCreator || (_userApplication?.isApproved ?? false);
  bool get isPending => _userApplication?.isPending ?? false;
  bool get isRejected => _userApplication?.isRejected ?? false;
  bool get isApplying => _isApplying;
  bool get isCreator => _auth.currentUser?.uid == _creatorId;
  
  // Participants
  List<Map<String, dynamic>> get approvedParticipants => _approvedParticipants;
  int get participantsCount => _approvedParticipants.length;
  
  /// Participantes visíveis (máximo 5)
  List<Map<String, dynamic>> get visibleParticipants => 
      _approvedParticipants.take(5).toList();
  
  /// Quantidade de participantes restantes (além dos 5 visíveis)
  int get remainingParticipantsCount => 
      participantsCount - visibleParticipants.length;
  
  /// Data formatada (hoje, amanhã, dia XX/XX)
  String get formattedDate => DateFormatter.formatDate(_scheduleDate);
  
  /// Horário formatado (HH:mm ou vazio se flexible)
  String get formattedTime => DateFormatter.formatTime(_scheduleDate);
  
  /// Retorna dados de localização para preload no PlaceCard
  /// Inclui visitantes aprovados para exibição imediata
  Map<String, dynamic>? get locationData {
    if (_preloadedEvent == null) return null;
    
    return {
      'locationName': _preloadedEvent!.locationName,
      'formattedAddress': _preloadedEvent!.formattedAddress,
      'placeId': _preloadedEvent!.placeId,
      'photoReferences': _preloadedEvent!.photoReferences,
      'visitors': _approvedParticipants.take(3).toList(), // Primeiros 3 visitantes
      'totalVisitorsCount': _approvedParticipants.length,
    };
  }
  
  /// Texto do botão baseado no estado
  String get buttonText {
    if (isCreator) return 'view_participants';
    if (isApplying) return 'applying';
    if (isApproved) return 'view_event_chat';
    if (isPending) return 'awaiting_approval';
    if (isRejected) return 'application_rejected';
    return privacyType == 'open' ? 'participate' : 'request_participation';
  }
  
  /// Texto do botão Chat (hardcoded para não depender de i18n)
  String get chatButtonText => 'Chat';
  
  /// Texto do botão Sair (hardcoded para não depender de i18n)
  String get leaveButtonText => 'Sair';
  
  /// Texto do botão Deletar para o owner (hardcoded para não depender de i18n)
  String get deleteButtonText => 'Deletar';
  
  /// Se o botão deve estar habilitado
  bool get isButtonEnabled {
    if (isCreator) return true;
    if (isApplying) return false;
    if (isApproved) return true;
    if (isPending || isRejected) return false;
    return true; // Pode aplicar
  }

  /// Pré-carrega apenas informações essenciais para renderizar o card instantaneamente.
  /// Isso roda ANTES de abrir o modal — deve ser muito rápido (60-120ms).
  /// 
  /// Card já abre com layout correto:
  /// - Botões certos (Chat + Sair se aprovado, ou Participar se não aplicou)
  /// - Estado do criador identificado
  /// - Privacy type carregado
  Future<void> preloadState() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    debugPrint('⚡ preloadState() iniciado (modo rápido)');
    final startTime = DateTime.now();

    // Se já veio do preloadedEvent, está pronto
    if (_preloadedEvent != null) {
      _creatorId = _preloadedEvent!.createdBy;
      _privacyType = _preloadedEvent!.privacyType;
      _userApplication = _preloadedEvent!.userApplication;
      _emoji = _preloadedEvent!.emoji;
      _activityText = _preloadedEvent!.title;
      _locationName = _preloadedEvent!.locationName;
      _creatorFullName = _preloadedEvent!.creatorFullName;
      _scheduleDate = _preloadedEvent!.scheduleDate;
      
      if (_preloadedEvent!.participants != null) {
        _approvedParticipants = _preloadedEvent!.participants!;
      }
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ preloadState() completo em ${duration}ms (dados pré-carregados)');
      return;
    }

    // Caso contrário, buscar APENAS dados mínimos do Firestore (paralelo)
    debugPrint('🔍 Buscando dados mínimos do Firestore...');
    
    try {
      // Buscar em paralelo: aplicação do usuário + dados essenciais do evento
      final results = await Future.wait([
        // 1. Application do usuário
        FirebaseFirestore.instance
            .collection('EventApplications')
            .where('eventId', isEqualTo: eventId)
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get(),
        
        // 2. Dados essenciais do evento
        FirebaseFirestore.instance
            .collection('Events')
            .doc(eventId)
            .get(),
      ]);

      // Processar application
      final appSnapshot = results[0] as QuerySnapshot;
      if (appSnapshot.docs.isNotEmpty) {
        _userApplication = EventApplicationModel.fromFirestore(appSnapshot.docs.first);
        debugPrint('✅ userApplication carregada: ${_userApplication!.status.value}');
      } else {
        debugPrint('ℹ️ userApplication: nenhuma encontrada');
      }

      // Processar evento
      final eventDoc = results[1] as DocumentSnapshot;
      if (eventDoc.exists) {
        final data = eventDoc.data() as Map<String, dynamic>;
        _creatorId = data['createdBy'] as String?;
        
        // Extrair privacyType de participants.privacyType
        final participantsData = data['participants'] as Map<String, dynamic>?;
        _privacyType = participantsData?['privacyType'] as String? ?? 'open';
        
        // Dados para exibição (opcional, mas bom ter)
        _emoji = data['emoji'] as String?;
        _activityText = data['activityText'] as String?;
        
        // Location
        final locationData = data['location'] as Map<String, dynamic>?;
        _locationName = locationData?['locationName'] as String?;
        
        debugPrint('✅ Dados essenciais do evento carregados');
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ preloadState() completo em ${duration}ms');
      debugPrint('   - isCreator: $isCreator');
      debugPrint('   - hasApplied: $hasApplied');
      debugPrint('   - isApproved: $isApproved');
      debugPrint('   - privacyType: $_privacyType');
      
    } catch (e) {
      debugPrint('❌ preloadState() erro: $e');
      // Não propaga erro - load() tentará novamente
    }
  }

  /// Carrega dados do evento de forma assíncrona (ANTES de abrir o widget)
  /// 
  /// Agora foca apenas em dados ADICIONAIS (participantes, criador fullName, etc).
  /// O essencial (isApproved, isCreator, privacyType) já vem do preloadState().
  Future<void> load() async {
    debugPrint('🔄 EventCardController.load() iniciado');
    
    try {
      // Se temos evento pré-carregado E já temos dados essenciais, pular busca
      if (_preloadedEvent != null && _privacyType != null) {
        debugPrint('✨ Dados essenciais já carregados via preloadState()');
      } else {
        // Fallback: buscar do Firestore (fluxo antigo)
        debugPrint('⚠️ Sem dados pré-carregados, buscando do Firestore...');
        await _loadEventData();
      }
      
      // Buscar dados ADICIONAIS (não-essenciais)
      
      // 1. Nome completo do criador (se ainda não tiver)
      if (_creatorFullName == null && _creatorId != null) {
        debugPrint('👤 Buscando nome do criador...');
        final userData = await _userRepo.getUserBasicInfo(_creatorId!);
        _creatorFullName = userData?['fullName'] as String?;
      }
      
      // 2. userApplication (se ainda não foi carregada)
      if (_userApplication == null) {
        debugPrint('🔍 Buscando userApplication (fallback)...');
        await _loadUserApplication();
      }
      
      // 3. Participantes aprovados (se não vieram pré-carregados)
      if (_preloadedEvent?.participants == null) {
        debugPrint('👥 Buscando lista de participantes...');
        await _loadApprovedParticipants();
      }
      
      _loaded = true;
      debugPrint('✅ EventCardController.load() finalizado');
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao carregar dados: $e';
      _loaded = false;
      debugPrint('❌ EventCardController.load() falhou: $e');
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
    debugPrint('🔄 EventCardController.applyToEvent iniciado');
    debugPrint('   - isApplying: $_isApplying');
    debugPrint('   - hasApplied: $hasApplied');
    debugPrint('   - privacyType: $_privacyType');
    
    if (_isApplying || hasApplied || _privacyType == null) {
      debugPrint('⚠️ Aplicação cancelada: isApplying=$_isApplying, hasApplied=$hasApplied, privacyType=$_privacyType');
      return;
    }
    
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      debugPrint('❌ Usuário não autenticado');
      throw Exception('Usuário não autenticado');
    }
    
    debugPrint('✅ Pré-condições OK, criando aplicação...');
    
    try {
      _isApplying = true;
      notifyListeners();
      
      final applicationId = await _applicationRepo.createApplication(
        eventId: eventId,
        userId: userId,
        eventPrivacyType: _privacyType!,
      );
      
      debugPrint('✅ Aplicação criada no Firestore: $applicationId');
      
      // Recarregar aplicação
      debugPrint('🔄 Recarregando aplicação do usuário...');
      await _loadUserApplication();
      
      debugPrint('✅ Aplicação recarregada:');
      debugPrint('   - hasApplied: $hasApplied');
      debugPrint('   - isApproved: $isApproved');
      debugPrint('   - isPending: $isPending');
      debugPrint('   - status: ${_userApplication?.status.value}');
      
    } catch (e) {
      debugPrint('❌ Erro ao aplicar: $e');
      rethrow;
    } finally {
      _isApplying = false;
      notifyListeners();
      debugPrint('🏁 applyToEvent finalizado');
    }
  }

  /// Remove a aplicação do usuário (sair do evento)
  Future<void> leaveEvent() async {
    debugPrint('🚪 EventCardController.leaveEvent iniciado');
    
    if (!hasApplied) {
      debugPrint('⚠️ Usuário não tem aplicação para remover');
      return;
    }
    
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      debugPrint('❌ Usuário não autenticado');
      throw Exception('Usuário não autenticado');
    }
    
    try {
      debugPrint('🔥 Chamando removeUserApplication via Cloud Function');
      await _applicationRepo.removeUserApplication(
        eventId: eventId,
        userId: userId,
      );
      
      debugPrint('✅ Aplicação removida com sucesso');
      
      // Limpar aplicação local
      _userApplication = null;
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Erro ao sair do evento: $e');
      rethrow;
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

