import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/services/location/distance_isolate.dart';

/// Serviço para buscar pessoas próximas via Cloud Function
/// 
/// 🔒 SEGURANÇA SERVER-SIDE:
/// - Limite de resultados aplicado no backend (Free: 17, VIP: 100)
/// - Ordenação VIP garantida pelo servidor
/// - Impossível burlar via client-side
/// 
/// ✅ PERFORMANCE:
/// - Reduz queries Firestore no client
/// - Filtros aplicados no servidor
/// - Distância calculada no client (melhor performance)
class PeopleCloudService {
  final _functions = FirebaseFunctions.instance;
  
  /// Converte Map<Object?, Object?> para Map<String, dynamic>
  /// 
  /// Firebase Cloud Functions retorna Map<Object?, Object?> que precisa
  /// ser convertido para Map<String, dynamic> para uso no Dart.
  Map<String, dynamic> _convertToStringDynamic(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) {
        final stringKey = key?.toString() ?? '';
        if (value is Map) {
          return MapEntry(stringKey, _convertToStringDynamic(value));
        } else if (value is List) {
          return MapEntry(stringKey, value.map((e) {
            if (e is Map) return _convertToStringDynamic(e);
            return e;
          }).toList());
        }
        return MapEntry(stringKey, value);
      });
    }
    return {};
  }
  
  /// Busca pessoas próximas usando Cloud Function
  /// 
  /// Parâmetros:
  /// - [userLatitude], [userLongitude]: Localização do usuário atual
  /// - [radiusKm]: Raio de busca em km
  /// - [boundingBox]: Bounding box calculado pelo GeoUtils
  /// - [filters]: Filtros avançados (gender, age, etc)
  /// 
  /// Retorna:
  /// - Lista de [UserWithDistance] já ordenada por VIP → Rating
  Future<PeopleCloudResult> getPeopleNearby({
    required double userLatitude,
    required double userLongitude,
    required double radiusKm,
    required Map<String, double> boundingBox,
    UserCloudFilters? filters,
  }) async {
    try {
      debugPrint('☁️ [PeopleCloud] Chamando Cloud Function getPeople...');
      debugPrint('   📍 User: ($userLatitude, $userLongitude)');
      debugPrint('   📏 Radius: ${radiusKm}km');
      debugPrint('   📦 BoundingBox: $boundingBox');
      debugPrint('   🔍 Filters: ${filters?.toMap()}');
      
      final startTime = DateTime.now();
      
      // Chamar Cloud Function
      final callable = _functions.httpsCallable(
        'getPeople',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 30),
        ),
      );
      
      debugPrint('☁️ [PeopleCloud] Executando chamada...');
      final result = await callable.call({
        'boundingBox': boundingBox,
        'filters': filters?.toMap(),
      });
      
      debugPrint('☁️ [PeopleCloud] Resposta recebida, processando dados...');
      
      // 🔧 Conversão segura de tipos (Firebase retorna Map<Object?, Object?>)
      final rawData = result.data;
      final data = _convertToStringDynamic(rawData);
      
      // Converter lista de usuários
      final rawUsers = data['users'] as List<dynamic>? ?? [];
      final users = rawUsers.map((u) => _convertToStringDynamic(u)).toList();
      
      final isVip = data['isVip'] as bool? ?? false;
      final limitApplied = data['limitApplied'] as int? ?? 0;
      final totalCandidates = data['totalCandidates'] as int? ?? 0;
      
      debugPrint('☁️ [PeopleCloud] Resposta recebida:');
      debugPrint('   👥 Usuários: ${users.length}');
      debugPrint('   👑 VIP: $isVip');
      debugPrint('   🔒 Limite aplicado: $limitApplied');
      debugPrint('   📊 Total candidatos: $totalCandidates');
      
      // Calcular distâncias no client (mais rápido que no servidor)
      final usersWithDistance = await _calculateDistances(
        users: users,
        centerLat: userLatitude,
        centerLng: userLongitude,
        radiusKm: radiusKm,
      );
      
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('☁️ [PeopleCloud] Processamento completo em ${elapsed}ms');
      
      return PeopleCloudResult(
        users: usersWithDistance,
        isVip: isVip,
        limitApplied: limitApplied,
        totalCandidates: totalCandidates,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [PeopleCloud] Erro ao buscar pessoas: $e');
      debugPrint('❌ [PeopleCloud] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Retorna apenas o total de candidatos dentro do bounding box (antes do limite).
  ///
  /// Útil para UI que precisa mostrar a contagem real no mapa,
  /// sem baixar lista nem calcular distâncias.
  Future<int> getPeopleCountInBounds({
    required Map<String, double> boundingBox,
    UserCloudFilters? filters,
  }) async {
    final callable = _functions.httpsCallable(
      'getPeople',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 30),
      ),
    );

    final result = await callable.call({
      'boundingBox': boundingBox,
      'filters': filters?.toMap(),
    });

    final data = _convertToStringDynamic(result.data);
    return (data['totalCandidates'] as int?) ?? 0;
  }
  
  /// Calcula distâncias em batch usando Isolate
  /// 
  /// 🚀 Performance: Processa em thread separada sem bloquear UI
  Future<List<UserWithDistance>> _calculateDistances({
    required List<Map<String, dynamic>> users,
    required double centerLat,
    required double centerLng,
    required double radiusKm,
  }) async {
    debugPrint('📊 [PeopleCloud] _calculateDistances: ${users.length} usuários para processar');
    
    if (users.isEmpty) {
      debugPrint('⚠️ [PeopleCloud] Lista de usuários vazia!');
      return [];
    }
    
    // Log do primeiro usuário para debug
    if (users.isNotEmpty) {
      final first = users.first;
      debugPrint('📊 [PeopleCloud] Primeiro usuário:');
      debugPrint('   - userId: ${first['userId']}');
      debugPrint('   - latitude: ${first['latitude']} (${first['latitude'].runtimeType})');
      debugPrint('   - longitude: ${first['longitude']} (${first['longitude'].runtimeType})');
    }
    
    // Converter para UserLocation
    final userLocations = <UserLocation>[];
    for (final userData in users) {
      try {
        final userId = userData['userId'] as String?;
        final lat = userData['latitude'];
        final lng = userData['longitude'];
        
        if (userId == null || lat == null || lng == null) {
          debugPrint('⚠️ [PeopleCloud] Usuário com dados inválidos: $userData');
          continue;
        }
        
        userLocations.add(UserLocation(
          userId: userId,
          latitude: (lat as num).toDouble(),
          longitude: (lng as num).toDouble(),
          userData: userData,
        ));
      } catch (e) {
        debugPrint('❌ [PeopleCloud] Erro ao converter usuário: $e');
        debugPrint('   - userData: $userData');
      }
    }
    
    debugPrint('📊 [PeopleCloud] ${userLocations.length} usuários convertidos com sucesso');
    
    if (userLocations.isEmpty) {
      debugPrint('⚠️ [PeopleCloud] Nenhum usuário válido após conversão!');
      return [];
    }
    
    // Calcular distâncias na thread principal (mais rápido para listas pequenas < 500 itens)
    // Evita overhead de serialização/startup de Isolate
    final filteredUsers = filterUsersByDistance(
      UserDistanceFilterRequest(
        users: userLocations,
        centerLat: centerLat,
        centerLng: centerLng,
        radiusKm: radiusKm,
      ),
    );

      debugPrint('📊 [PeopleCloud] ${filteredUsers.length} usuários após filtro de distância');

      return filteredUsers;
  }
}

/// Filtros para busca de pessoas (enviados para Cloud Function)
class UserCloudFilters {
  final String? gender;
  final int? minAge;
  final int? maxAge;
  final bool? isVerified;
  final List<String>? interests;
  final String? sexualOrientation;
  
  const UserCloudFilters({
    this.gender,
    this.minAge,
    this.maxAge,
    this.isVerified,
    this.interests,
    this.sexualOrientation,
  });
  
  Map<String, dynamic> toMap() {
    return {
      if (gender != null) 'gender': gender,
      if (minAge != null) 'minAge': minAge,
      if (maxAge != null) 'maxAge': maxAge,
      if (isVerified != null) 'isVerified': isVerified,
      if (interests != null && interests!.isNotEmpty) 'interests': interests,
      if (sexualOrientation != null) 'sexualOrientation': sexualOrientation,
    };
  }
}

/// Resultado da busca via Cloud Function
class PeopleCloudResult {
  final List<UserWithDistance> users;
  final bool isVip;
  final int limitApplied;
  final int totalCandidates;
  
  const PeopleCloudResult({
    required this.users,
    required this.isVip,
    required this.limitApplied,
    required this.totalCandidates,
  });
}
