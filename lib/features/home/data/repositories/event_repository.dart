import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Repository centralizado para queries da coleção events
/// 
/// Evita duplicação de código ao reutilizar queries comuns
class EventRepository {
  final FirebaseFirestore _firestore;

  EventRepository([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Referência à coleção events
  CollectionReference get _eventsCollection => _firestore.collection('events');

  /// Busca um evento por ID
  /// 
  /// Retorna null se não encontrado
  Future<Map<String, dynamic>?> getEventById(String eventId) async {
    try {
      final doc = await _eventsCollection.doc(eventId).get();
      
      if (!doc.exists) {
        debugPrint('⚠️ Evento não encontrado: $eventId');
        return null;
      }

      return {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar evento $eventId: $e');
      return null;
    }
  }

  /// Busca dados básicos de um evento (para cards, listas, etc)
  /// 
  /// Retorna:
  /// - id
  /// - emoji
  /// - activityText
  /// - locationName (extraído de location.locationName)
  /// - scheduleDate (convertido de schedule.date Timestamp → DateTime)
  /// - privacyType (extraído de participants.privacyType)
  /// - createdBy (userId do criador)
  Future<Map<String, dynamic>?> getEventBasicInfo(String eventId) async {
    try {
      final doc = await _eventsCollection.doc(eventId).get();
      
      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      
      // Extrair dados aninhados
      final locationData = data['location'] as Map<String, dynamic>?;
      final scheduleData = data['schedule'] as Map<String, dynamic>?;
      final participantsData = data['participants'] as Map<String, dynamic>?;
      final dateTimestamp = scheduleData?['date'] as Timestamp?;

      return {
        'id': eventId,
        'emoji': data['emoji'] as String?,
        'activityText': data['activityText'] as String?,
        'locationName': locationData?['locationName'] as String?,
        'scheduleDate': dateTimestamp?.toDate(),
        'privacyType': participantsData?['privacyType'] as String?,
        'createdBy': data['createdBy'] as String?,
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar info básica do evento $eventId: $e');
      return null;
    }
  }

  /// Busca dados completos de um evento (incluindo campos aninhados parseados)
  Future<Map<String, dynamic>?> getEventFullInfo(String eventId) async {
    try {
      final doc = await _eventsCollection.doc(eventId).get();
      
      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      
      // Parsear campos aninhados
      final locationData = data['location'] as Map<String, dynamic>?;
      final scheduleData = data['schedule'] as Map<String, dynamic>?;
      final participantsData = data['participants'] as Map<String, dynamic>?;

      return {
        'id': eventId,
        ...data,
        // Adicionar campos parseados para facilitar acesso
        'locationName': locationData?['locationName'] as String?,
        'locationGeoPoint': locationData?['geoPoint'] as GeoPoint?,
        'scheduleDate': (scheduleData?['date'] as Timestamp?)?.toDate(),
        'scheduleFlexible': scheduleData?['flexible'] as bool? ?? false,
        'privacyType': participantsData?['privacyType'] as String?,
        'maxParticipants': participantsData?['maxParticipants'] as int?,
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar info completa do evento $eventId: $e');
      return null;
    }
  }

  /// Busca múltiplos eventos por IDs (batch otimizado)
  Future<Map<String, Map<String, dynamic>>> getEventsByIds(List<String> eventIds) async {
    if (eventIds.isEmpty) return {};

    try {
      final results = <String, Map<String, dynamic>>{};
      
      // Dividir em chunks de 10 (limite do whereIn)
      for (var i = 0; i < eventIds.length; i += 10) {
        final chunk = eventIds.skip(i).take(10).toList();
        
        final snapshot = await _eventsCollection
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snapshot.docs) {
          results[doc.id] = {
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          };
        }
      }

      return results;
    } catch (e) {
      debugPrint('❌ Erro ao buscar eventos por IDs: $e');
      return {};
    }
  }

  /// Stream de dados do evento (para listeners em tempo real)
  Stream<Map<String, dynamic>?> watchEvent(String eventId) {
    return _eventsCollection
        .doc(eventId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return {
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          };
        });
  }

  /// Busca eventos criados por um usuário
  Future<List<Map<String, dynamic>>> getEventsByCreator(String userId) async {
    try {
      final snapshot = await _eventsCollection
          .where('createdBy', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => {
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              })
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar eventos do criador $userId: $e');
      return [];
    }
  }

  /// Atualiza dados de um evento
  Future<void> updateEvent(String eventId, Map<String, dynamic> data) async {
    try {
      await _eventsCollection.doc(eventId).update(data);
      debugPrint('✅ Evento atualizado: $eventId');
    } catch (e) {
      debugPrint('❌ Erro ao atualizar evento $eventId: $e');
      rethrow;
    }
  }

  /// Cria um novo evento
  Future<String> createEvent(Map<String, dynamic> data) async {
    try {
      final docRef = await _eventsCollection.add(data);
      debugPrint('✅ Evento criado: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Erro ao criar evento: $e');
      rethrow;
    }
  }

  /// Deleta um evento
  Future<void> deleteEvent(String eventId) async {
    try {
      await _eventsCollection.doc(eventId).delete();
      debugPrint('✅ Evento deletado: $eventId');
    } catch (e) {
      debugPrint('❌ Erro ao deletar evento $eventId: $e');
      rethrow;
    }
  }

  /// Verifica se evento existe
  Future<bool> eventExists(String eventId) async {
    try {
      final doc = await _eventsCollection.doc(eventId).get();
      return doc.exists;
    } catch (e) {
      debugPrint('❌ Erro ao verificar existência do evento $eventId: $e');
      return false;
    }
  }
}
