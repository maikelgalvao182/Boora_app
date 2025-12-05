import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controller para gerenciar estado do ListDrawer
/// 
/// Responsabilidades:
/// - Escutar streams de eventos do usuário (seus eventos criados)
/// 
/// NOTA: A funcionalidade de "eventos próximos" foi REMOVIDA.
/// LocationQueryService agora busca apenas USUÁRIOS (pessoas), não eventos.
/// Para eventos próximos, use o mapa (AppleMapViewModel + EventMapRepository).
class ListDrawerController extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // Estado processado
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _myEvents = [];
  bool _isLoadingMyEvents = true;
  String? _error;

  // Subscriptions
  StreamSubscription<QuerySnapshot>? _myEventsSubscription;

  ListDrawerController({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    _initialize();
  }

  // Getters - Estado processado e pronto para UI
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get myEvents => _myEvents;
  bool get isLoadingMyEvents => _isLoadingMyEvents;
  bool get isLoading => _isLoadingMyEvents;
  String? get error => _error;
  
  bool get hasMyEvents => _myEvents.isNotEmpty;
  bool get isEmpty => !_isLoadingMyEvents && _myEvents.isEmpty;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Inicializa listeners das streams
  void _initialize() {
    final userId = currentUserId;
    
    if (userId == null) {
      _error = 'Usuário não autenticado';
      _isLoadingMyEvents = false;
      notifyListeners();
      return;
    }

    // Stream: Eventos criados pelo usuário
    _myEventsSubscription = _firestore
        .collection('events')
        .where('createdBy', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          _onMyEventsChanged,
          onError: _onMyEventsError,
        );
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

  /// Recarrega os dados
  void refresh() {
    _isLoadingMyEvents = true;
    _error = null;
    notifyListeners();
    
    // A stream já vai recarregar automaticamente
    debugPrint('🔄 ListDrawerController: Refresh solicitado');
  }

  @override
  void dispose() {
    _myEventsSubscription?.cancel();
    super.dispose();
  }
}
