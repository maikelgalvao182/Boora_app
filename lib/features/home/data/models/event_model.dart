/// Modelo simplificado de evento para exibição no mapa
class EventModel {
  final String id;
  final String emoji;
  final String createdBy;
  final double lat;
  final double lng;
  final String title;
  final String? locationName;

  EventModel({
    required this.id,
    required this.emoji,
    required this.createdBy,
    required this.lat,
    required this.lng,
    required this.title,
    this.locationName,
  });

  /// Factory para criar EventModel a partir de um Map
  factory EventModel.fromMap(Map<String, dynamic> map, String id) {
    return EventModel(
      id: id,
      emoji: map['emoji'] as String? ?? '🎉',
      createdBy: map['createdBy'] as String? ?? '',
      lat: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      lng: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      title: map['activityText'] as String? ?? '',
      locationName: map['locationName'] as String?,
    );
  }
}
