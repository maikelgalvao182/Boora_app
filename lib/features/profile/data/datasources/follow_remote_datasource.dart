import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FollowRemoteDataSource {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> followUser(String targetUid) async {
    debugPrint('📡 [FollowDataSource] followUser($targetUid) - Chamando Cloud Function...');
    final callable = _functions.httpsCallable(
      'followUser',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final result = await callable.call({'targetUid': targetUid});
    debugPrint('📡 [FollowDataSource] followUser resultado: ${result.data}');
  }

  Future<void> unfollowUser(String targetUid) async {
    debugPrint('📡 [FollowDataSource] unfollowUser($targetUid) - Chamando Cloud Function...');
    final callable = _functions.httpsCallable(
      'unfollowUser',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final result = await callable.call({'targetUid': targetUid});
    debugPrint('📡 [FollowDataSource] unfollowUser resultado: ${result.data}');
  }

  Stream<bool> isFollowing(String myUid, String targetUid) {
    debugPrint('📡 [FollowDataSource] isFollowing($myUid, $targetUid) - Criando stream...');
    return _firestore
        .collection('Users')
        .doc(myUid)
        .collection('following')
        .doc(targetUid)
        .snapshots()
        .map((snapshot) {
          final exists = snapshot.exists;
          debugPrint('📡 [FollowDataSource] Snapshot recebido: exists=$exists');
          return exists;
        });
  }
}
