import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

/// Repositório para buscar eventos próximos no mapa
class EventMapRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream de eventos ativos próximos à localização do usuário (TEMPO REAL)
  /// 
  /// NOTA: Este stream NÃO aplica filtro de raio.
  /// Retorna TODOS os eventos ativos e NÃO cancelados em tempo real.
  /// A distância/disponibilidade são calculadas posteriormente pelo MapViewModel.
  /// 
  /// ✅ Reage automaticamente a: criação, atualização e deleção de eventos
  Stream<List<EventModel>> getEventsStream() {
    return _firestore
        .collection('events')
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'active')
        .snapshots() // Removido includeMetadataChanges: true — dobrava snapshots sem necessidade
        .map((snapshot) {
      debugPrint('🔄 [EventMapRepository] Snapshot source: ${snapshot.metadata.isFromCache ? "CACHE" : "SERVER"}');
      debugPrint('🔄 [EventMapRepository] Snapshot changes: ${snapshot.docChanges.length}');
      
      // Log das mudanças (added, modified, removed)
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          debugPrint('🗑️ [EventMapRepository] Evento REMOVIDO: ${change.doc.id}');
        } else if (change.type == DocumentChangeType.added) {
          debugPrint('➕ [EventMapRepository] Evento ADICIONADO: ${change.doc.id}');
        } else if (change.type == DocumentChangeType.modified) {
          debugPrint('✏️ [EventMapRepository] Evento MODIFICADO: ${change.doc.id}');
        }
      }
      
      final events = <EventModel>[];
      
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          
          // Filtrar eventos cancelados (dupla checagem no cliente)
          final isCanceled = data['isCanceled'] as bool? ?? false;
          if (isCanceled) {
            debugPrint('⏭️ Evento ${doc.id} está cancelado, pulando...');
            continue;
          }

          final location = data['location'] as Map<String, dynamic>?;
          if (location == null) continue;

          final lat = (location['latitude'] as num?)?.toDouble();
          final lng = (location['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;

          // Extrair dados adicionais
          final participantsData = data['participants'] as Map<String, dynamic>?;
          final scheduleData = data['schedule'] as Map<String, dynamic>?;
          final dateTimestamp = scheduleData?['date'] as Timestamp?;
          
          // Parse photoReferences
          List<String>? photoReferences;
          final photoRefs = location['photoReferences'] as List<dynamic>?;
          if (photoRefs != null) {
            photoReferences = photoRefs.map((e) => e.toString()).toList();
          }

          final event = EventModel(
            id: doc.id,
            emoji: data['emoji'] as String? ?? '🎉',
            createdBy: data['createdBy'] as String? ?? '',
            lat: lat,
            lng: lng,
            title: data['activityText'] as String? ?? '',
            category: (data['category'] as String?)?.trim(),
            locationName: location['locationName'] as String?,
            formattedAddress: location['formattedAddress'] as String?,
            placeId: location['placeId'] as String?,
            photoReferences: photoReferences,
            scheduleDate: dateTimestamp?.toDate(),
            privacyType: participantsData?['privacyType'] as String?,
            minAge: participantsData?['minAge'] as int?,
            maxAge: participantsData?['maxAge'] as int?,
            gender: participantsData?['gender'] as String?,
          );
          
          // 🔍 DEBUG: Log campos críticos para diagnóstico
          if (event.locationName == null || event.privacyType == null || event.title.isEmpty) {
            debugPrint('⚠️ [EventMapRepository] Evento ${doc.id} com dados incompletos:');
            debugPrint('   - activityText: ${data['activityText']}');
            debugPrint('   - location keys: ${location.keys.toList()}');
            debugPrint('   - location.locationName: ${location['locationName']}');
            debugPrint('   - participants keys: ${participantsData?.keys.toList()}');
            debugPrint('   - participants.privacyType: ${participantsData?['privacyType']}');
          }
          
          events.add(event);
        } catch (e) {
          debugPrint('⚠️ Erro ao processar evento ${doc.id}: $e');
        }
      }
      
      debugPrint('🔄 [EventMapRepository] Stream emitiu ${events.length} eventos');
      return events;
    });
  }

  /// Busca eventos ativos próximos à localização do usuário (SNAPSHOT ÚNICO)
  /// 
  /// Parâmetros:
  /// - [userLocation]: Localização atual do usuário
  /// 
  /// NOTA: Este método NÃO aplica filtro de raio.
  /// Retorna TODOS os eventos ativos e NÃO cancelados.
  /// A distância/disponibilidade são calculadas posteriormente pelo MapViewModel.
  /// 
  /// ⚠️ DEPRECATED: Use getEventsStream() para atualizações em tempo real
  Future<List<EventModel>> getEventsWithinRadius(
    LatLng userLocation,
  ) async {
    try {
      debugPrint('📍 [EventMapRepository] Buscando eventos próximos...');

      // Buscar eventos ativos e não cancelados
      final snapshot = await _firestore
          .collection('events')
          .where('isActive', isEqualTo: true)
          .where('status', isEqualTo: 'active')
          .get();

      final events = <EventModel>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          
          // Filtrar eventos cancelados (dupla checagem no cliente)
          final isCanceled = data['isCanceled'] as bool? ?? false;
          if (isCanceled) {
            debugPrint('⏭️ Evento ${doc.id} está cancelado, pulando...');
            continue;
          }

          final location = data['location'] as Map<String, dynamic>?;

          if (location == null) continue;

          final lat = (location['latitude'] as num?)?.toDouble();
          final lng = (location['longitude'] as num?)?.toDouble();

          if (lat == null || lng == null) continue;

          // Extrair dados adicionais para pré-carregar no EventCard
          final participantsData = data['participants'] as Map<String, dynamic>?;
          final scheduleData = data['schedule'] as Map<String, dynamic>?;
          final dateTimestamp = scheduleData?['date'] as Timestamp?;
          
          // Parse photoReferences
          List<String>? photoReferences;
          final photoRefs = location['photoReferences'] as List<dynamic>?;
          if (photoRefs != null) {
            photoReferences = photoRefs.map((e) => e.toString()).toList();
          }

          // Criar evento com TODOS os campos disponíveis
          // A distância/disponibilidade/userApplication serão enriquecidos pelo MapViewModel._enrichEvents()
          final event = EventModel(
            id: doc.id,
            emoji: data['emoji'] as String? ?? '🎉',
            createdBy: data['createdBy'] as String? ?? '',
            lat: lat,
            lng: lng,
            title: data['activityText'] as String? ?? '',
            category: (data['category'] as String?)?.trim(),
            locationName: location['locationName'] as String?,
            formattedAddress: location['formattedAddress'] as String?,
            placeId: location['placeId'] as String?,
            photoReferences: photoReferences,
            scheduleDate: dateTimestamp?.toDate(),
            privacyType: participantsData?['privacyType'] as String?,
            minAge: participantsData?['minAge'] as int?,
            maxAge: participantsData?['maxAge'] as int?,
          );
          events.add(event);
        } catch (e) {
          debugPrint('⚠️ Erro ao processar evento ${doc.id}: $e');
        }
      }

      debugPrint('✅ [EventMapRepository] ${events.length} eventos encontrados');
      return events;
    } catch (e) {
      debugPrint('❌ [EventMapRepository] Erro ao buscar eventos: $e');
      return [];
    }
  }

  /// Busca um evento específico pelo ID
  /// Inclui dados do criador como participante para exibição imediata
  Future<EventModel?> getEventById(String eventId, {bool includeCreatorAsParticipant = true}) async {
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      
      if (!doc.exists) return null;
      
      final data = doc.data();
      if (data == null) return null;

      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      final lat = (location['latitude'] as num?)?.toDouble();
      final lng = (location['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final creatorId = data['createdBy'] as String? ?? '';

      final participantsData = data['participants'] as Map<String, dynamic>?;
      final scheduleData = data['schedule'] as Map<String, dynamic>?;
      final dateTimestamp = scheduleData?['date'] as Timestamp?;

      List<String>? photoReferences;
      final photoRefs = location['photoReferences'] as List<dynamic>?;
      if (photoRefs != null) {
        photoReferences = photoRefs.map((e) => e.toString()).toList();
      }

      // Buscar dados do criador para pré-popular lista de participantes
      String? creatorFullName;
      String? creatorPhotoUrl;
      List<Map<String, dynamic>>? participants;

      if (includeCreatorAsParticipant && creatorId.isNotEmpty) {
        try {
          final creatorDoc = await _firestore.collection('Users').doc(creatorId).get();
          if (creatorDoc.exists) {
            final creatorData = creatorDoc.data();
            creatorFullName = creatorData?['fullName'] as String?;
            creatorPhotoUrl = creatorData?['photoUrl'] as String?;

            participants = [
              {
                'userId': creatorId,
                'fullName': creatorFullName ?? 'Anônimo',
                'photoUrl': creatorPhotoUrl ?? '',
                'isCreator': true,
              }
            ];
          }
        } catch (e) {
          debugPrint('⚠️ [EventMapRepository] Erro ao buscar dados do criador: $e');
        }
      }

      return EventModel(
        id: doc.id,
        emoji: data['emoji'] as String? ?? '🎉',
        createdBy: creatorId,
        creatorFullName: creatorFullName,
        lat: lat,
        lng: lng,
        title: data['activityText'] as String? ?? '',
        category: (data['category'] as String?)?.trim(),
        locationName: location['locationName'] as String?,
        formattedAddress: location['formattedAddress'] as String?,
        placeId: location['placeId'] as String?,
        photoReferences: photoReferences,
        scheduleDate: dateTimestamp?.toDate(),
        privacyType: participantsData?['privacyType'] as String?,
        minAge: participantsData?['minAge'] as int?,
        maxAge: participantsData?['maxAge'] as int?,
        gender: participantsData?['gender'] as String?,
        participants: participants,
      );
    } catch (e) {
      debugPrint('❌ [EventMapRepository] Erro ao buscar evento por ID: $e');
      return null;
    }
  }
}
