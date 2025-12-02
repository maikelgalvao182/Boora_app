import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Modelo de atividade exibida no mapa
/// Representa eventos, locais ou pontos de interesse
class ActivityModel extends Equatable {
  /// ID único da atividade
  final String id;
  
  /// Nome ou título da atividade
  final String name;
  
  /// Descrição detalhada
  final String description;
  
  /// Latitude da localização
  final double latitude;
  
  /// Longitude da localização
  final double longitude;
  
  /// Tipo de atividade (ex: 'wedding', 'party', 'meeting')
  final String type;
  
  /// Emoji ou ícone representativo
  final String emoji;
  
  /// URL da imagem (opcional)
  final String? imageUrl;
  
  /// Data do evento (opcional)
  final DateTime? eventDate;
  
  /// Número de participantes
  final int participantCount;
  
  /// Indica se o usuário está participando
  final bool isParticipating;
  
  /// Data de criação
  final DateTime createdAt;

  const ActivityModel({
    required this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.emoji = '📍',
    this.imageUrl,
    this.eventDate,
    this.participantCount = 0,
    this.isParticipating = false,
    required this.createdAt,
  });

  /// Cria uma instância a partir de um documento Firestore
  factory ActivityModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    
    // Extrai coordenadas de diferentes formatos possíveis
    double? lat;
    double? lng;
    
    // Tenta extrair de diferentes campos
    if (data['latitude'] != null && data['longitude'] != null) {
      lat = (data['latitude'] as num).toDouble();
      lng = (data['longitude'] as num).toDouble();
    } else if (data['location'] is GeoPoint) {
      final geoPoint = data['location'] as GeoPoint;
      lat = geoPoint.latitude;
      lng = geoPoint.longitude;
    } else if (data['geo_point']?['geopoint'] != null) {
      final geoData = data['geo_point']['geopoint'];
      lat = (geoData['_latitude'] ?? geoData['latitude'] as num?)?.toDouble();
      lng = (geoData['_longitude'] ?? geoData['longitude'] as num?)?.toDouble();
    }
    
    // Validação obrigatória
    if (lat == null || lng == null) {
      throw Exception('Coordenadas inválidas no documento ${doc.id}');
    }
    
    return ActivityModel(
      id: doc.id,
      name: data['name'] as String? ?? data['event_name'] as String? ?? 'Sem nome',
      description: data['description'] as String? ?? data['brief'] as String? ?? '',
      latitude: lat,
      longitude: lng,
      type: data['type'] as String? ?? 'event',
      emoji: _getEmojiForType(data['type'] as String?),
      imageUrl: data['image_url'] as String? ?? data['coverPhoto'] as String?,
      eventDate: data['event_date'] != null 
          ? (data['event_date'] as Timestamp).toDate() 
          : null,
      participantCount: data['participant_count'] as int? ?? 
                        data['guestCount'] as int? ?? 0,
      isParticipating: data['is_participating'] as bool? ?? false,
      createdAt: data['created_at'] != null
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Retorna emoji apropriado baseado no tipo de atividade
  static String _getEmojiForType(String? type) {
    switch (type?.toLowerCase()) {
      case 'wedding':
        return '💒';
      case 'party':
        return '🎉';
      case 'meeting':
        return '🤝';
      case 'restaurant':
        return '🍽️';
      case 'cafe':
        return '☕';
      case 'bar':
        return '🍺';
      case 'club':
        return '🎵';
      case 'outdoor':
        return '🌳';
      case 'sports':
        return '⚽';
      case 'cultural':
        return '🎭';
      default:
        return '📍';
    }
  }

  /// Converte para JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'emoji': emoji,
      'image_url': imageUrl,
      'event_date': eventDate?.toIso8601String(),
      'participant_count': participantCount,
      'is_participating': isParticipating,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Cria cópia com alterações
  ActivityModel copyWith({
    String? id,
    String? name,
    String? description,
    double? latitude,
    double? longitude,
    String? type,
    String? emoji,
    String? imageUrl,
    DateTime? eventDate,
    int? participantCount,
    bool? isParticipating,
    DateTime? createdAt,
  }) {
    return ActivityModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      emoji: emoji ?? this.emoji,
      imageUrl: imageUrl ?? this.imageUrl,
      eventDate: eventDate ?? this.eventDate,
      participantCount: participantCount ?? this.participantCount,
      isParticipating: isParticipating ?? this.isParticipating,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        latitude,
        longitude,
        type,
        emoji,
        imageUrl,
        eventDate,
        participantCount,
        isParticipating,
        createdAt,
      ];
}
