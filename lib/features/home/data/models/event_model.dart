import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';

/// Modelo simplificado de evento para exibição no mapa
class EventModel {
  final String id;
  final String emoji;
  final String createdBy;
  final double lat;
  final double lng;
  final String title;
  final String? category;
  final String? locationName;
  final String? formattedAddress;
  final String? placeId;
  final List<String>? photoReferences;
  final double? distanceKm;
  final bool isAvailable;
  final String? creatorFullName;
  final DateTime? scheduleDate;
  final String? privacyType;
  final List<Map<String, dynamic>>? participants;
  final EventApplicationModel? userApplication; // Aplicação do usuário atual (pré-carregada)
  final bool isAgeRestricted; // Pré-calculado: se o usuário não atende às restrições de idade
  final int? minAge; // Idade mínima do evento
  final int? maxAge; // Idade máxima do evento

  EventModel({
    required this.id,
    required this.emoji,
    required this.createdBy,
    required this.lat,
    required this.lng,
    required this.title,
    this.category,
    this.locationName,
    this.formattedAddress,
    this.placeId,
    this.photoReferences,
    this.distanceKm,
    this.isAvailable = true,
    this.creatorFullName,
    this.scheduleDate,
    this.privacyType,
    this.participants,
    this.userApplication,
    this.isAgeRestricted = false,
    this.minAge,
    this.maxAge,
  });

  /// Factory para criar EventModel a partir de um Map
  factory EventModel.fromMap(Map<String, dynamic> map, String id) {
    // DEBUG: Ver o que está vindo no map
    if (!map.containsKey('privacyType')) {
      debugPrint('⚠️ EventModel.fromMap: privacyType AUSENTE no map do evento $id');
      debugPrint('   Campos disponíveis: ${map.keys.toList()}');
    } else {
      debugPrint('✅ EventModel.fromMap: privacyType = ${map['privacyType']} (evento $id)');
    }
    
    // Tentar extrair coordenadas da raiz ou do objeto location
    final location = map['location'] as Map<String, dynamic>?;
    final lat = (map['latitude'] as num?)?.toDouble() ?? 
                (location?['latitude'] as num?)?.toDouble() ?? 
                0.0;
    final lng = (map['longitude'] as num?)?.toDouble() ?? 
                (location?['longitude'] as num?)?.toDouble() ?? 
                0.0;
    
    final locationName = map['locationName'] as String? ?? 
                         location?['locationName'] as String?;
    
    final formattedAddress = map['formattedAddress'] as String? ??
                            location?['formattedAddress'] as String?;
    
    final placeId = map['placeId'] as String? ??
                   location?['placeId'] as String?;
    
    // Parse photoReferences
    List<String>? photoReferences;
    final photoRefs = map['photoReferences'] as List<dynamic>?;
    if (photoRefs != null) {
      photoReferences = photoRefs.map((e) => e.toString()).toList();
    }

    // Parse scheduleDate
    DateTime? scheduleDate;
    
    // 1. Se já vier como DateTime (ex: de repositórios que já converteram)
    if (map['scheduleDate'] is DateTime) {
      scheduleDate = map['scheduleDate'] as DateTime;
    }
    // 2. Se vier como String (ex: JSON/ISO8601)
    else if (map['scheduleDate'] is String) {
      try {
        scheduleDate = DateTime.parse(map['scheduleDate'] as String);
      } catch (_) {}
    }
    // 3. Se vier na estrutura raw do Firestore (schedule map com date Timestamp)
    else if (map['schedule'] is Map) {
      final scheduleMap = map['schedule'] as Map<String, dynamic>;
      final dateField = scheduleMap['date'];
      
      if (dateField is Timestamp) {
        scheduleDate = dateField.toDate();
      } else if (dateField is String) {
        try {
          scheduleDate = DateTime.parse(dateField);
        } catch (_) {}
      }
    }

    return EventModel(
      id: id,
      emoji: map['emoji'] as String? ?? '🎉',
      createdBy: map['createdBy'] as String? ?? '',
      lat: lat,
      lng: lng,
      title: map['activityText'] as String? ?? '',
      category: (map['category'] as String?)?.trim(),
      locationName: locationName,
      formattedAddress: formattedAddress,
      placeId: placeId,
      photoReferences: photoReferences,
      distanceKm: (map['distanceKm'] as num?)?.toDouble(),
      isAvailable: map['isAvailable'] as bool? ?? true,
      creatorFullName: map['creatorFullName'] as String?,
      scheduleDate: scheduleDate,
      // Se privacyType não existe, usar "open" como padrão (todos eventos são abertos por padrão)
      privacyType: map['privacyType'] as String? ?? 'open',
      participants: null, // Não vem do map inicial
      isAgeRestricted: map['isAgeRestricted'] as bool? ?? false,
    )..debugPrintFields(id);
  }
  
  /// Debug: Imprime campos críticos para diagnóstico
  void debugPrintFields(String id) {
    debugPrint('📊 [EventModel] Criado evento $id:');
    debugPrint('   - title (activityText): $title');
    debugPrint('   - locationName: $locationName');
    debugPrint('   - creatorFullName: $creatorFullName');
    debugPrint('   - privacyType: $privacyType');
    debugPrint('   - createdBy: $createdBy');
  }

  /// Cria uma cópia com campos atualizados
  EventModel copyWith({
    String? id,
    String? emoji,
    String? createdBy,
    double? lat,
    double? lng,
    String? title,
    String? category,
    String? locationName,
    String? formattedAddress,
    String? placeId,
    List<String>? photoReferences,
    double? distanceKm,
    bool? isAvailable,
    String? creatorFullName,
    DateTime? scheduleDate,
    String? privacyType,
    List<Map<String, dynamic>>? participants,
    EventApplicationModel? userApplication,
    bool? isAgeRestricted,
    int? minAge,
    int? maxAge,
  }) {
    return EventModel(
      id: id ?? this.id,
      emoji: emoji ?? this.emoji,
      createdBy: createdBy ?? this.createdBy,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      title: title ?? this.title,
      category: category ?? this.category,
      locationName: locationName ?? this.locationName,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      placeId: placeId ?? this.placeId,
      photoReferences: photoReferences ?? this.photoReferences,
      distanceKm: distanceKm ?? this.distanceKm,
      isAvailable: isAvailable ?? this.isAvailable,
      creatorFullName: creatorFullName ?? this.creatorFullName,
      scheduleDate: scheduleDate ?? this.scheduleDate,
      privacyType: privacyType ?? this.privacyType,
      participants: participants ?? this.participants,
      userApplication: userApplication ?? this.userApplication,
      isAgeRestricted: isAgeRestricted ?? this.isAgeRestricted,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
    );
  }
}
