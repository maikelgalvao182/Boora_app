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
        .where('status', isEqualTo: 'active')
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
              .collection('users_preview')
              .where(FieldPath.documentId, whereIn: userIds)
              .get();

          final usersMap = {
            for (var doc in usersSnapshot.docs) doc.id: doc.data()
          };

          // 4. Montar modelos
          final applications = <PendingApplicationModel>[];

          for (final doc in appsSnapshot.docs) {
            final data = doc.data();
            debugPrint('🔍 Application doc.id: ${doc.id}');
            debugPrint('🔍 Application data: $data');
            
            final eventId = data['eventId'] as String;
            final applicantId = data['userId'] as String;
            
            debugPrint('🔍 eventId: $eventId');
            debugPrint('🔍 applicantId (userId): $applicantId');

            final eventData = eventsMap[eventId];
            final userData = usersMap[applicantId] ?? _buildFallbackUserData(data);
            
            debugPrint('🔍 eventData found: ${eventData != null}');
            debugPrint('🔍 userData found: ${userData != null}');
            debugPrint('🔍 userData: $userData');

            if (eventData != null && userData != null) {
              try {
                final model = PendingApplicationModel.fromCombined(
                  applicationId: doc.id,
                  applicationData: data,
                  userData: userData,
                  eventData: eventData,
                );
                debugPrint('✅ Model criado - userId: ${model.userId}, userName: ${model.userFullName}, photoUrl: ${model.userPhotoUrl}');
                applications.add(model);
              } catch (e) {
                debugPrint('❌ Erro ao converter aplicação ${doc.id}: $e');
              }
            } else {
              debugPrint('⚠️ Dados faltando para doc ${doc.id} - eventData: ${eventData != null}, userData: ${userData != null}');
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
      }, onError: (error) {
        final isPermissionDenied =
            error is FirebaseException && error.code == 'permission-denied';
        final isLoggedOut = _auth.currentUser == null;
        
        // Silenciar permission-denied após logout
        if (isPermissionDenied && isLoggedOut) {
          appsSub?.cancel();
          if (!controller.isClosed) controller.add([]);
          return;
        }

        // Só loga se não for permission-denied durante logout
        if (!isPermissionDenied) {
          debugPrint('❌ Erro no stream de aplicações: $error');
        }
        if (!controller.isClosed) controller.add([]);
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

  Map<String, dynamic>? _buildFallbackUserData(Map<String, dynamic> applicationData) {
    final name = applicationData['user_fullname'] as String? ??
        applicationData['userFullname'] as String? ??
        applicationData['fullname'] as String? ??
        applicationData['fullName'] as String? ??
        applicationData['user_name'] as String? ??
        applicationData['userName'] as String?;

    final photoUrl = applicationData['user_photo_url'] as String? ??
        applicationData['userPhotoUrl'] as String? ??
        applicationData['photo_url'] as String? ??
        applicationData['photoUrl'] as String? ??
        applicationData['avatarThumbUrl'] as String? ??
        applicationData['avatar_thumb_url'] as String? ??
        applicationData['image'] as String?;

    if ((name == null || name.isEmpty) && (photoUrl == null || photoUrl.isEmpty)) {
      return null;
    }

    return {
      if (name != null) 'fullName': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
    };
  }
}
