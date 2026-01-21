import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/features/home/data/models/event_model.dart';

/// Busca eventos recentes para o seletor do composer.
/// MVP: pega eventos onde o usuário tem aplicação aprovada/autoApproved.
class RecentEventsService {
  RecentEventsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<List<EventModel>> fetchRecentEligibleEvents({int limit = 20}) async {
    print('🎯 [RecentEventsService] Iniciando fetchRecentEligibleEvents - limit: $limit');
    
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      print('❌ [RecentEventsService] Usuário não autenticado');
      throw Exception('Usuário não autenticado');
    }
    
    print('👤 [RecentEventsService] userId: $uid');

    // EventApplications tem userId e status. Vamos buscar as mais recentes.
    print('🔍 [RecentEventsService] Buscando EventApplications...');
    print('   Query: userId == $uid, status in [approved, autoApproved], orderBy(appliedAt, desc), limit: $limit');
    
  try {
      final apps = await _firestore
          .collection('EventApplications')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: ['approved', 'autoApproved'])
    // O schema/índices do projeto usam `appliedAt` para ordenar aplicações.
    // Usar `createdAt` força criação de índice extra e pode falhar em produção.
    .orderBy('appliedAt', descending: true)
          .limit(limit)
          .get();

      print('✅ [RecentEventsService] EventApplications encontradas: ${apps.docs.length}');
      
      final eventIds = apps.docs
          .map((d) => (d.data()['eventId'] as String?))
          .whereType<String>()
          .where((e) => e.trim().isNotEmpty)
          .toSet()
          .toList(growable: false);

      print('📋 [RecentEventsService] EventIds únicos: ${eventIds.length}');
      
      if (eventIds.isEmpty) {
        print('⚠️ [RecentEventsService] Nenhum eventId encontrado');
        return const [];
      }

      // Firestore whereIn max 30. Vamos chunkear em blocos de 10-20 por segurança.
      final out = <EventModel>[];
      const chunkSize = 10;

      for (var i = 0; i < eventIds.length; i += chunkSize) {
        final chunk = eventIds.sublist(i, (i + chunkSize).clamp(0, eventIds.length));
        print('🔍 [RecentEventsService] Buscando eventos (chunk ${i ~/ chunkSize + 1}): ${chunk.length} ids');

        final eventsSnap = await _firestore
            .collection('events')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        print('✅ [RecentEventsService] Eventos encontrados no chunk: ${eventsSnap.docs.length}');
        
        for (final doc in eventsSnap.docs) {
          out.add(EventModel.fromMap(doc.data(), doc.id));
        }
      }

      print('✅ [RecentEventsService] Total de eventos carregados: ${out.length}');
      
      // Ordena por scheduleDate (desc), fallback id.
      out.sort((a, b) {
        final ad = a.scheduleDate;
        final bd = b.scheduleDate;
        if (ad == null && bd == null) return b.id.compareTo(a.id);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      return out.take(limit).toList(growable: false);
    } catch (e, stack) {
      print('❌ [RecentEventsService] ERRO ao buscar eventos elegíveis: $e');
      print('📚 Stack trace: $stack');
      rethrow;
    }
  }
}
