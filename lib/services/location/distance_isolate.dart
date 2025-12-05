import 'dart:math';

/// Isolate worker para cálculo de distâncias em background
/// 
/// Evita jank na UI ao processar grandes volumes de eventos
/// Usa compute() do Flutter para simplicidade

/// Entrada para o isolate
class DistanceFilterRequest {
  final List<EventLocation> events;
  final double centerLat;
  final double centerLng;
  final double radiusKm;

  const DistanceFilterRequest({
    required this.events,
    required this.centerLat,
    required this.centerLng,
    required this.radiusKm,
  });
}

/// Dados de localização de um evento (classe leve para isolate)
class EventLocation {
  final String eventId;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> eventData;

  const EventLocation({
    required this.eventId,
    required this.latitude,
    required this.longitude,
    required this.eventData,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'latitude': latitude,
        'longitude': longitude,
        'eventData': eventData,
      };

  factory EventLocation.fromJson(Map<String, dynamic> json) {
    return EventLocation(
      eventId: json['eventId'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      eventData: json['eventData'] as Map<String, dynamic>,
    );
  }
}

/// Resultado do filtro com distância calculada
class EventWithDistance {
  final String eventId;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final Map<String, dynamic> eventData;

  const EventWithDistance({
    required this.eventId,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.eventData,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'latitude': latitude,
        'longitude': longitude,
        'distanceKm': distanceKm,
        'eventData': eventData,
      };

  factory EventWithDistance.fromJson(Map<String, dynamic> json) {
    return EventWithDistance(
      eventId: json['eventId'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      distanceKm: json['distanceKm'] as double,
      eventData: json['eventData'] as Map<String, dynamic>,
    );
  }
}

/// Função principal do isolate - DEVE ser top-level
/// 
/// Filtra eventos por distância usando Haversine
/// Retorna apenas eventos dentro do raio
List<EventWithDistance> filterEventsByDistance(
  DistanceFilterRequest request,
) {
  final results = <EventWithDistance>[];

  for (final event in request.events) {
    final distance = _calculateHaversineDistance(
      lat1: request.centerLat,
      lng1: request.centerLng,
      lat2: event.latitude,
      lng2: event.longitude,
    );

    // Apenas eventos dentro do raio
    if (distance <= request.radiusKm) {
      results.add(
        EventWithDistance(
          eventId: event.eventId,
          latitude: event.latitude,
          longitude: event.longitude,
          distanceKm: distance,
          eventData: event.eventData,
        ),
      );
    }
  }

  // Ordenar por distância (mais próximos primeiro)
  results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

  return results;
}

/// Cálculo de Haversine (versão pura - sem dependências)
/// 
/// IMPORTANTE: Deve ser função pura para funcionar no isolate
double _calculateHaversineDistance({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  const earthRadiusKm = 6371.0;

  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

/// Converte graus para radianos
double _toRadians(double degrees) {
  return degrees * pi / 180.0;
}

// ========== NOVAS CLASSES E FUNÇÕES PARA USUÁRIOS ==========

/// Entrada para o isolate - versão para usuários
class UserDistanceFilterRequest {
  final List<UserLocation> users;
  final double centerLat;
  final double centerLng;
  final double radiusKm;

  const UserDistanceFilterRequest({
    required this.users,
    required this.centerLat,
    required this.centerLng,
    required this.radiusKm,
  });
}

/// Dados de localização de um usuário (classe leve para isolate)
class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> userData;

  const UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.userData,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'userData': userData,
      };

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      userId: json['userId'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      userData: json['userData'] as Map<String, dynamic>,
    );
  }
}

/// Resultado do filtro com distância calculada - versão para usuários
class UserWithDistance {
  final String userId;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final Map<String, dynamic> userData;

  const UserWithDistance({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.userData,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'distanceKm': distanceKm,
        'userData': userData,
      };

  factory UserWithDistance.fromJson(Map<String, dynamic> json) {
    return UserWithDistance(
      userId: json['userId'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      distanceKm: json['distanceKm'] as double,
      userData: json['userData'] as Map<String, dynamic>,
    );
  }
}

/// Função principal do isolate para usuários - DEVE ser top-level
/// 
/// Filtra usuários por distância usando Haversine
/// Retorna apenas usuários dentro do raio
List<UserWithDistance> filterUsersByDistance(
  UserDistanceFilterRequest request,
) {
  final results = <UserWithDistance>[];

  for (final user in request.users) {
    final distance = _calculateHaversineDistance(
      lat1: request.centerLat,
      lng1: request.centerLng,
      lat2: user.latitude,
      lng2: user.longitude,
    );

    // Apenas usuários dentro do raio
    if (distance <= request.radiusKm) {
      results.add(
        UserWithDistance(
          userId: user.userId,
          latitude: user.latitude,
          longitude: user.longitude,
          distanceKm: distance,
          userData: user.userData,
        ),
      );
    }
  }

  // Ordenar por distância (mais próximos primeiro)
  results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

  return results;
}
