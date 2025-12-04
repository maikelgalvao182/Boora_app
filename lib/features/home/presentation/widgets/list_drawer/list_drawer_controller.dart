import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/distance_isolate.dart';

/// Controller para gerenciar estado do ListDrawer
/// 
/// Responsabilidades:
/// - Escutar streams de eventos do usuário
/// - Escutar stream de eventos próximos (LocationQueryService)
/// - Filtrar eventos próximos (excluir os do próprio usuário)
/// - Expor estado processado para o widget
class ListDrawerController extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LocationQueryService _locationService;

  // Estado processado
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _myEvents = [];
  List<EventWithDistance> _nearbyEvents = [];
  bool _isLoadingMyEvents = true;
  bool _isLoadingNearby = true;
  String? _error;

  // Subscriptions
  StreamSubscription<QuerySnapshot>? _myEventsSubscription;
  StreamSubscription<List<EventWithDistance>>? _nearbyEventsSubscription;

  ListDrawerController({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    LocationQueryService? locationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _locationService = locationService ?? LocationQueryService() {
    _initialize();
  }

  // Getters - Estado processado e pronto para UI
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get myEvents => _myEvents;
  List<EventWithDistance> get nearbyEvents => _nearbyEvents;
  bool get isLoadingMyEvents => _isLoadingMyEvents;
  bool get isLoadingNearby => _isLoadingNearby;
  bool get isLoading => _isLoadingMyEvents || _isLoadingNearby;
  String? get error => _error;
  
  bool get hasMyEvents => _myEvents.isNotEmpty;
  bool get hasNearbyEvents => _nearbyEvents.isNotEmpty;
  bool get isEmpty => !_isLoadingMyEvents && !_isLoadingNearby && _myEvents.isEmpty && _nearbyEvents.isEmpty;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Inicializa listeners das streams
  void _initialize() {
    final userId = currentUserId;
    
    if (userId == null) {
      _error = 'Usuário não autenticado';
      _isLoadingMyEvents = false;
      _isLoadingNearby = false;
      notifyListeners();
      return;
    }

    // Stream 1: Eventos criados pelo usuário
    _myEventsSubscription = _firestore
        .collection('events')
        .where('createdBy', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          _onMyEventsChanged,
          onError: _onMyEventsError,
        );

    // Stream 2: Eventos próximos (filtrados por raio)
    _nearbyEventsSubscription = _locationService.eventsStream.listen(
      _onNearbyEventsChanged,
      onError: _onNearbyEventsError,
    );

    // Carregar dados iniciais de eventos próximos
    // Necessário pois a stream é broadcast e pode já ter emitido o valor atual antes do listen
    _loadInitialNearbyEvents();
  }

  /// Carrega dados iniciais de eventos próximos
  Future<void> _loadInitialNearbyEvents() async {
    try {
      final events = await _locationService.getEventsWithinRadiusOnce();
      _onNearbyEventsChanged(events);
    } catch (e) {
      _onNearbyEventsError(e);
    }
  }

  /// Handler para mudanças nos eventos do usuário
  void _onMyEventsChanged(QuerySnapshot snapshot) {
    _myEvents = snapshot.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
    _isLoadingMyEvents = false;
    notifyListeners();
    debugPrint('✅ ListDrawerController: ${_myEvents.length} eventos do usuário carregados');
  }

  /// Handler para erros nos eventos do usuário
  void _onMyEventsError(dynamic error) {
    _error = 'Erro ao carregar suas atividades';
    _isLoadingMyEvents = false;
    notifyListeners();
    debugPrint('❌ ListDrawerController: Erro ao carregar eventos do usuário: $error');
  }

  /// Handler para mudanças nos eventos próximos
  void _onNearbyEventsChanged(List<EventWithDistance> events) {
    // Filtrar eventos do próprio usuário (já aparecem em "Suas atividades")
    _nearbyEvents = events.where((event) {
      final createdBy = event.eventData['createdBy'] as String?;
      return createdBy != null && createdBy != currentUserId;
    }).toList();
    
    _isLoadingNearby = false;
    notifyListeners();
    debugPrint('✅ ListDrawerController: ${_nearbyEvents.length} eventos próximos carregados (${events.length} total)');
  }

  /// Handler para erros nos eventos próximos
  void _onNearbyEventsError(dynamic error) {
    _error = 'Erro ao carregar atividades próximas';
    _isLoadingNearby = false;
    notifyListeners();
    debugPrint('❌ ListDrawerController: Erro ao carregar eventos próximos: $error');
  }

  /// Recarrega os dados
  void refresh() {
    _isLoadingMyEvents = true;
    _isLoadingNearby = true;
    _error = null;
    notifyListeners();
    
    // As streams já vão recarregar automaticamente
    debugPrint('🔄 ListDrawerController: Refresh solicitado');
  }

  @override
  void dispose() {
    _myEventsSubscription?.cancel();
    _nearbyEventsSubscription?.cancel();
    super.dispose();
  }
}
