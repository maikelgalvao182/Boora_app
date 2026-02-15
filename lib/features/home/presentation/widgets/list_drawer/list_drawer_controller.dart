import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controller para gerenciar estado do ListDrawer
/// 
/// Responsabilidades:
/// - Escutar streams de eventos do usuário (seus eventos criados)
/// 
/// ✅ SINGLETON com ValueNotifiers para evitar rebuilds desnecessários
/// ✅ Cache mantido entre aberturas do drawer
/// 
/// NOTA: A funcionalidade de "eventos próximos" foi REMOVIDA.
/// LocationQueryService agora busca apenas USUÁRIOS (pessoas), não eventos.
/// Para eventos próximos, use o mapa (AppleMapViewModel + EventMapRepository).
class ListDrawerController {
  // Singleton
  static final ListDrawerController _instance = ListDrawerController._internal();
  factory ListDrawerController() => _instance;
  
  ListDrawerController._internal() {
    debugPrint('🎉 ListDrawerController: Singleton criado');
    _initialize();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Estado usando ValueNotifiers (rebuild granular)
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>> myEvents = 
      ValueNotifier([]);
  final ValueNotifier<bool> isLoadingMyEvents = ValueNotifier(true);
  final ValueNotifier<String?> error = ValueNotifier(null);

  // Subscriptions
  StreamSubscription<QuerySnapshot>? _myEventsSubscription;
  StreamSubscription<User?>? _authSubscription;

  // Getters convenientes
  bool get hasMyEvents => myEvents.value.isNotEmpty;
  bool get isEmpty => !isLoadingMyEvents.value && myEvents.value.isEmpty;
  String? get currentUserId => _auth.currentUser?.uid;

  /// Inicializa listeners das streams
  void _initialize() {
    _authSubscription ??= _auth.authStateChanges().listen((user) {
      if (user == null) {
        reset();
        return;
      }

      if (_myEventsSubscription != null) return;
      _startMyEventsStream(user.uid);
    });

    final userId = currentUserId;
    if (userId != null) {
      _startMyEventsStream(userId);
      return;
    }

    // Sem usuário: mantém estado vazio e aguarda auth listener.
    reset();
  }

  void _startMyEventsStream(String userId) {
    error.value = null;
    isLoadingMyEvents.value = true;

    _myEventsSubscription?.cancel();
    _myEventsSubscription = _firestore
        .collection('events')
        .where('createdBy', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20) // Limite para reduzir leituras Firestore
        .snapshots()
        .listen(
          _onMyEventsChanged,
          onError: _onMyEventsError,
        );
  }

  /// Handler para mudanças nos eventos do usuário
  void _onMyEventsChanged(QuerySnapshot snapshot) {
    final docs = snapshot.docs
        .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
        .where((doc) {
      final data = doc.data();

      final isCanceled = data['isCanceled'] as bool? ?? false;
      if (isCanceled) return false;

      final status = data['status'] as String?;
      if (status != 'active') return false;

      return true;
    }).toList();

    myEvents.value = docs;
    isLoadingMyEvents.value = false;
    debugPrint('✅ ListDrawerController: ${myEvents.value.length} eventos do usuário carregados');
  }

  /// Handler para erros nos eventos do usuário
  void _onMyEventsError(dynamic err) {
    final isPermissionDenied = err is FirebaseException && err.code == 'permission-denied';
    if (isPermissionDenied && currentUserId == null) {
      // Logout: o stream pode estourar permission-denied antes do cancel.
      reset();
      return;
    }

    error.value = 'Erro ao carregar suas atividades';
    isLoadingMyEvents.value = false;
    debugPrint('❌ ListDrawerController: Erro ao carregar eventos do usuário: $err');
  }

  /// Recarrega os dados
  void refresh() {
    isLoadingMyEvents.value = true;
    error.value = null;
    
    // A stream já vai recarregar automaticamente
    debugPrint('🔄 ListDrawerController: Refresh solicitado');
  }

  void dispose() {
    // Singleton não deve ser disposto
    debugPrint('⚠️ ListDrawerController: dispose() chamado (singleton não será destruído)');
  }

  void reset() {
    _myEventsSubscription?.cancel();
    _myEventsSubscription = null;

    myEvents.value = [];
    isLoadingMyEvents.value = false;
    error.value = null;
  }
}
