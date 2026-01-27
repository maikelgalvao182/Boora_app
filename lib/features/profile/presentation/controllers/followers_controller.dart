import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

class FollowersController {
  FollowersController({required this.userId});

  final String userId;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserRepository _userRepository = UserRepository();

  final ValueNotifier<List<User>> followers = ValueNotifier(const []);
  final ValueNotifier<List<User>> following = ValueNotifier(const []);

  final ValueNotifier<bool> isLoadingFollowers = ValueNotifier(false);
  final ValueNotifier<bool> isLoadingFollowing = ValueNotifier(false);

  final ValueNotifier<Object?> followersError = ValueNotifier(null);
  final ValueNotifier<Object?> followingError = ValueNotifier(null);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followingSub;

  int _followersRequestId = 0;
  int _followingRequestId = 0;

  void initialize() {
    _listenFollowers();
    _listenFollowing();
  }

  void _listenFollowers() {
    final query = _firestore
        .collection('Users')
        .doc(userId)
        .collection('followers')
        .orderBy('createdAt', descending: true);

    _followersSub = query.snapshots().listen(
      (snapshot) => _handleFollowersSnapshot(snapshot),
      onError: (error) {
        _setNotifierValue(followersError, error);
        _setNotifierValue(isLoadingFollowers, false);
      },
    );
  }

  void _listenFollowing() {
    final query = _firestore
        .collection('Users')
        .doc(userId)
        .collection('following')
        .orderBy('createdAt', descending: true);

    _followingSub = query.snapshots().listen(
      (snapshot) => _handleFollowingSnapshot(snapshot),
      onError: (error) {
        _setNotifierValue(followingError, error);
        _setNotifierValue(isLoadingFollowing, false);
      },
    );
  }

  Future<void> refreshFollowers() async {
    final requestId = ++_followersRequestId;
    _setNotifierValue(isLoadingFollowers, true);
    _setNotifierValue(followersError, null);

    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('followers')
          .orderBy('createdAt', descending: true)
          .get();

      await _applyFollowersSnapshot(snapshot, requestId);
    } catch (e) {
      _setNotifierValue(followersError, e);
      _setNotifierValue(isLoadingFollowers, false);
    }
  }

  Future<void> refreshFollowing() async {
    final requestId = ++_followingRequestId;
    _setNotifierValue(isLoadingFollowing, true);
    _setNotifierValue(followingError, null);

    try {
      final snapshot = await _firestore
          .collection('Users')
          .doc(userId)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .get();

      await _applyFollowingSnapshot(snapshot, requestId);
    } catch (e) {
      _setNotifierValue(followingError, e);
      _setNotifierValue(isLoadingFollowing, false);
    }
  }

  Future<void> _handleFollowersSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final requestId = ++_followersRequestId;
    _setNotifierValue(followersError, null);
    await _applyFollowersSnapshot(snapshot, requestId);
  }

  Future<void> _handleFollowingSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final requestId = ++_followingRequestId;
    _setNotifierValue(followingError, null);
    await _applyFollowingSnapshot(snapshot, requestId);
  }

  Future<void> _applyFollowersSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int requestId,
  ) async {
    final users = await _buildUsersFromSnapshot(snapshot, requestId, isFollowers: true);

    if (requestId != _followersRequestId) {
      return;
    }

    _setNotifierValue(followers, users);
    _setNotifierValue(isLoadingFollowers, false);
  }

  Future<void> _applyFollowingSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int requestId,
  ) async {
    final users = await _buildUsersFromSnapshot(snapshot, requestId, isFollowers: false);

    if (requestId != _followingRequestId) {
      return;
    }

    _setNotifierValue(following, users);
    _setNotifierValue(isLoadingFollowing, false);
  }

  Future<List<User>> _buildUsersFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int requestId, {
    required bool isFollowers,
  }) async {
    final ids = snapshot.docs.map((doc) => doc.id).toList();
    if (ids.isEmpty) {
      return const [];
    }

    final futures = ids.map(_userRepository.getUserById).toList();
    final results = await Future.wait(futures);

    if (isFollowers && requestId != _followersRequestId) {
      return const [];
    }
    if (!isFollowers && requestId != _followingRequestId) {
      return const [];
    }

    final users = <User>[];
    for (var i = 0; i < results.length; i++) {
      final data = results[i];
      if (data == null) continue;
      final normalized = <String, dynamic>{
        ...data,
        'userId': ids[i],
      };
      users.add(User.fromDocument(normalized).copyWith(distance: null));
    }

    return users;
  }

  void _setNotifierValue<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value == value) return;
    scheduleMicrotask(() {
      if (notifier.value != value) {
        notifier.value = value;
      }
    });
  }

  void dispose() {
    _followersSub?.cancel();
    _followingSub?.cancel();
    followers.dispose();
    following.dispose();
    isLoadingFollowers.dispose();
    isLoadingFollowing.dispose();
    followersError.dispose();
    followingError.dispose();
  }
}
