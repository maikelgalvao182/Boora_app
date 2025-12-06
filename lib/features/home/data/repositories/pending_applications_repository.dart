import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/data/models/pending_application_model.dart';

/// Repository para buscar aplicações pendentes dos eventos do usuário
class PendingApplicationsRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  PendingApplicationsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Stream de aplicações pendentes para eventos criados pelo usuário atual
  /// 
  /// Retorna stream que emite lista de PendingApplicationModel sempre que houver mudança
  /// Agora reativo a mudanças tanto em eventos quanto em aplicações
  Stream<List<PendingApplicationModel>> getPendingApplicationsStream() {
    final controller = StreamController<List<PendingApplicationModel>>();
    final userId = _auth.currentUser?.uid;
    
    debugPrint('📡 PendingApplicationsRepository: Iniciando stream reativo');
    
    if (userId == null) {
      controller.add([]);
      return controller.stream;
    }

    StreamSubscription? eventsSub;
    StreamSubscription? appsSub;

    // 1. Escutar eventos do usuário
    eventsSub = _firestore
        .collection('events')
        .where('createdBy', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .where('isCanceled', isEqualTo: false)
        .snapshots()
        .listen((eventsSnapshot) {
      
      if (eventsSnapshot.docs.isEmpty) {
        appsSub?.cancel();
        controller.add([]);
        return;
      }

      final eventIds = eventsSnapshot.docs.map((doc) => doc.id).toList();
      final eventsMap = {
        for (var doc in eventsSnapshot.docs) doc.id: doc.data()
      };

      // Cancelar listener anterior de aplicações
      appsSub?.cancel();

      // 2. Escutar aplicações para esses eventos
      // Nota: Firestore limita 'whereIn' a 10 itens.
      // Pegamos os 10 primeiros (mais recentes/relevantes) para evitar erro.
      final targetEventIds = eventIds.take(10).toList();

      appsSub = _firestore
          .collection('EventApplications')
          .where('eventId', whereIn: targetEventIds)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((appsSnapshot) async {
            
        if (appsSnapshot.docs.isEmpty) {
          if (!controller.isClosed) controller.add([]);
          return;
        }

        try {
          // 3. Buscar dados dos usuários (não dá para fazer stream disso facilmente, então fazemos get)
          final userIds = appsSnapshot.docs
              .map((doc) => doc.data()['userId'] as String)
              .toSet()
              .toList();

          if (userIds.isEmpty) {
            if (!controller.isClosed) controller.add([]);
            return;
          }

          final usersSnapshot = await _firestore
              .collection('Users')
              .where(FieldPath.documentId, whereIn: userIds)
              .get();

          final usersMap = {
            for (var doc in usersSnapshot.docs) doc.id: doc.data()
          };

          // 4. Montar modelos
          final applications = <PendingApplicationModel>[];

          for (final doc in appsSnapshot.docs) {
            final data = doc.data();
            final eventId = data['eventId'] as String;
            final applicantId = data['userId'] as String;

            final eventData = eventsMap[eventId];
            final userData = usersMap[applicantId];

            if (eventData != null && userData != null) {
              try {
                final model = PendingApplicationModel.fromCombined(
                  applicationId: doc.id,
                  applicationData: data,
                  userData: userData,
                  eventData: eventData,
                );
                applications.add(model);
              } catch (e) {
                debugPrint('❌ Erro ao converter aplicação ${doc.id}: $e');
              }
            }
          }

          // Ordenar por data (mais recente primeiro)
          applications.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
          
          if (!controller.isClosed) {
            controller.add(applications);
            debugPrint('📊 PendingApplicationsRepository: Emitindo ${applications.length} aplicações');
          }
        } catch (e) {
          debugPrint('❌ Erro ao processar aplicações: $e');
          if (!controller.isClosed) controller.add([]);
        }
      });
      
    }, onError: (e) {
      debugPrint('❌ Erro no stream de eventos: $e');
      if (!controller.isClosed) controller.add([]);
    });

    controller.onCancel = () {
      eventsSub?.cancel();
      appsSub?.cancel();
    };

    return controller.stream;
  }
}
