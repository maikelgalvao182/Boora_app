import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/distance_isolate.dart';

/// Controller para gerenciar a lista de pessoas próximas
/// 
/// Usa LocationQueryService para buscar usuários dentro do raio configurado
/// com filtros sociais (gênero, idade, verificado, interesses)
class FindPeopleController extends ChangeNotifier {
  FindPeopleController() {
    _initializeStream();
  }

  // Serviço de localização
  final LocationQueryService _locationService = LocationQueryService();
  
  // Subscription do stream
  StreamSubscription<List<UserWithDistance>>? _usersSubscription;

  // Estado
  bool _isLoading = true;
  String? _error;
  List<User> _users = [];

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<User> get users => _users;
  List<String> get userIds => _users.map((u) => u.userId).toList();
  bool get isEmpty => _users.isEmpty && !_isLoading;

  /// Inicializa stream de usuários próximos
  void _initializeStream() {
    debugPrint('🔍 FindPeopleController: Inicializando stream de usuários');
    
    // Carregar usuários inicialmente (sem aguardar)
    _loadInitialUsers();
    
    // Escutar stream de atualizações automáticas
    _usersSubscription = _locationService.usersStream.listen(
      _onUsersChanged,
      onError: _onUsersError,
    );
  }

  /// Carrega usuários inicialmente
  Future<void> _loadInitialUsers() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      debugPrint('🔍 FindPeopleController: Carregando usuários próximos...');
      
      final usersWithDistance = await _locationService.getUsersWithinRadiusOnce();
      
      await _convertToUsers(usersWithDistance);
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ FindPeopleController: Erro ao carregar usuários: $e');
      _error = 'Erro ao carregar pessoas próximas';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Callback quando usuários mudam no stream
  void _onUsersChanged(List<UserWithDistance> usersWithDistance) async {
    debugPrint('🔄 FindPeopleController: Stream recebeu ${usersWithDistance.length} usuários');
    
    await _convertToUsers(usersWithDistance);
    
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Callback quando ocorre erro no stream
  void _onUsersError(Object error) {
    debugPrint('❌ FindPeopleController: Erro no stream: $error');
    
    _error = 'Erro ao carregar pessoas próximas';
    _isLoading = false;
    notifyListeners();
  }

  /// Converte UserWithDistance para User
  Future<void> _convertToUsers(List<UserWithDistance> usersWithDistance) async {
    final currentUserId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    
    // Carregar interesses do usuário atual para calcular commonInterests
    List<String> myInterests = [];
    if (currentUserId != null) {
      try {
        final myDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUserId)
            .get();
        if (myDoc.exists) {
          myInterests = List<String>.from(myDoc.data()?['interests'] ?? []);
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao carregar interesses do usuário atual: $e');
      }
    }

    final List<User> loadedUsers = [];
    
    for (final userWithDist in usersWithDistance) {
      final data = Map<String, dynamic>.from(userWithDist.userData);
      
      // Adicionar campos computados
      data['userId'] = userWithDist.userId;
      data['distance'] = userWithDist.distanceKm;
      
      // Calcular interesses em comum
      final userInterests = List<String>.from(data['interests'] ?? []);
      final common = userInterests.toSet().intersection(myInterests.toSet()).toList();
      data['commonInterests'] = common;
      
      loadedUsers.add(User.fromDocument(data));
    }
    
    // Ordenar por distância (mais próximos primeiro)
    loadedUsers.sort((a, b) {
      final distA = a.distance ?? double.infinity;
      final distB = b.distance ?? double.infinity;
      return distA.compareTo(distB);
    });

    _users = loadedUsers;
    
    debugPrint('📋 FindPeopleController: ${_users.length} usuários carregados');
  }

  /// Recarrega a lista forçando invalidação do cache
  Future<void> refresh() async {
    debugPrint('🔄 FindPeopleController: Refresh solicitado');
    _locationService.forceReload();
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    super.dispose();
  }
}

