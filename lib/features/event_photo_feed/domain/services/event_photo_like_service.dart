import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class EventPhotoLikeService {
  EventPhotoLikeService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _photos => _firestore.collection('EventPhotos');

  Stream<int> watchLikesCount(String photoId) {
    return _photos.doc(photoId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      return (data['likesCount'] as num?)?.toInt() ?? 0;
    });
  }

  Stream<bool> watchIsLiked(String photoId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return Stream<bool>.value(false);
    }

    return _photos
        .doc(photoId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<bool> toggleLike({
    required String photoId,
    required bool currentlyLiked,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      final i18n = await AppLocalizations.loadForLanguageCode(AppLocalizations.currentLocale);
      throw Exception(i18n.translate('user_not_authenticated'));
    }

    final photoRef = _photos.doc(photoId);
    final likeRef = photoRef.collection('likes').doc(uid);

    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(photoRef);
      final data = snap.data() ?? const <String, dynamic>{};
      final currentCount = (data['likesCount'] as num?)?.toInt() ?? 0;

      if (currentlyLiked) {
        tx.delete(likeRef);
        tx.update(photoRef, {
          'likesCount': currentCount > 0 ? currentCount - 1 : 0,
        });
        return false;
      }

      tx.set(likeRef, {
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(photoRef, {
        'likesCount': currentCount + 1,
      }, SetOptions(merge: true));

      return true;
    });
  }
}
