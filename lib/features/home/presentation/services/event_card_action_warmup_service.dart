import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/home/data/models/event_application_model.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

class EventCardActionWarmupState {
  final EventApplicationModel? userApplication;
  final bool? isUserVip;
  final bool? isGenderRestricted;
  final String? currentUserGender;
  final bool? isAgeRestricted;
  final int? userAge;

  const EventCardActionWarmupState({
    this.userApplication,
    this.isUserVip,
    this.isGenderRestricted,
    this.currentUserGender,
    this.isAgeRestricted,
    this.userAge,
  });
}

/// Servico para pre-carregar o estado do botao do EventCard.
///
/// Objetivo: evitar loading no primeiro open do card ao aquecer
/// application do usuario, restricao de genero e status VIP.
class EventCardActionWarmupService {
  static final EventCardActionWarmupService _instance =
      EventCardActionWarmupService._internal();

  factory EventCardActionWarmupService({
    EventApplicationRepository? applicationRepo,
    UserRepository? userRepo,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) {
    _instance._overrideDependencies(
      applicationRepo: applicationRepo,
      userRepo: userRepo,
      auth: auth,
      firestore: firestore,
    );
    return _instance;
  }

  EventCardActionWarmupService._internal()
      : _applicationRepo = EventApplicationRepository(),
        _userRepo = UserRepository(),
        _auth = FirebaseAuth.instance,
        _firestore = FirebaseFirestore.instance;

  EventApplicationRepository _applicationRepo;
  UserRepository _userRepo;
  FirebaseAuth _auth;
  FirebaseFirestore _firestore;

  void _overrideDependencies({
    EventApplicationRepository? applicationRepo,
    UserRepository? userRepo,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) {
    if (applicationRepo != null) _applicationRepo = applicationRepo;
    if (userRepo != null) _userRepo = userRepo;
    if (auth != null) _auth = auth;
    if (firestore != null) _firestore = firestore;
  }

  static EventCardActionWarmupService get instance => _instance;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _shouldCancel = false;

  final Set<String> _warmedUpEvents = {};
  final Map<String, EventCardActionWarmupState> _stateCache = {};

  static const int _maxEventsPerCycle = 15;
  static const Duration _perEventTimeout = Duration(seconds: 2);

  EventCardActionWarmupState? getState(String eventId) => _stateCache[eventId];

  void cancel() {
    _shouldCancel = true;
  }

  void clearCache() {
    _warmedUpEvents.clear();
    _stateCache.clear();
  }

  Future<void> warmupActionStateForEvents(
    List<EventModel> events, {
    int? maxEvents,
  }) async {
    if (_isRunning) {
      debugPrint('[ActionWarmup] Ja esta rodando, ignorando chamada');
      return;
    }

    if (events.isEmpty) return;

    final userId = _auth.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;

    final effectiveMaxEvents = maxEvents ?? _maxEventsPerCycle;

    _isRunning = true;
    _shouldCancel = false;

    try {
      final eventsToWarmup = events
          .where((e) => !_warmedUpEvents.contains(e.id))
          .take(effectiveMaxEvents)
          .toList();

      if (eventsToWarmup.isEmpty) return;

        final userData = await _userRepo.getCurrentUserData();
        final currentUserGender = userData?['gender'] as String?;
        final currentUserAgeRaw = userData?['age'];
        final currentUserAge = currentUserAgeRaw is int
          ? currentUserAgeRaw
          : (currentUserAgeRaw is num ? currentUserAgeRaw.toInt() : null);

      bool? cachedVipStatus;
      final needsVipCheck = eventsToWarmup.any((e) => !e.isAvailable);
      if (needsVipCheck) {
        cachedVipStatus = await _fetchVipStatus(userId);
      }

      for (final event in eventsToWarmup) {
        if (_shouldCancel) break;

        final isCreator = event.createdBy == userId;

        EventApplicationModel? userApplication;
        if (!isCreator) {
          try {
            userApplication = await _applicationRepo
                .getUserApplication(eventId: event.id, userId: userId)
                .timeout(_perEventTimeout);
          } catch (_) {
            userApplication = null;
          }
        }

        bool? isGenderRestricted;
        final requiredGender = event.gender;
        if (requiredGender != null && requiredGender != GENDER_ALL) {
          if (isCreator) {
            isGenderRestricted = false;
          } else if (currentUserGender == null || currentUserGender.isEmpty) {
            isGenderRestricted = true;
          } else {
            isGenderRestricted = currentUserGender != requiredGender;
          }
        }

        bool? isAgeRestricted;
        if (isCreator) {
          isAgeRestricted = false;
        } else if (event.minAge != null && event.maxAge != null) {
          if (currentUserAge == null) {
            isAgeRestricted = true;
          } else {
            isAgeRestricted =
                currentUserAge < event.minAge! || currentUserAge > event.maxAge!;
          }
        }

        _stateCache[event.id] = EventCardActionWarmupState(
          userApplication: userApplication,
          isUserVip: cachedVipStatus,
          isGenderRestricted: isGenderRestricted,
          currentUserGender: currentUserGender,
          isAgeRestricted: isAgeRestricted,
          userAge: currentUserAge,
        );
        _warmedUpEvents.add(event.id);

        await Future.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _isRunning = false;
      _shouldCancel = false;
    }
  }

  Future<bool?> _fetchVipStatus(String userId) async {
    try {
      final userPreviewDoc =
          await _firestore.collection('users_preview').doc(userId).get();
      if (!userPreviewDoc.exists) return false;

      final data = userPreviewDoc.data();
      if (data == null) return false;

      final rawVip =
          data['IsVip'] ?? data['user_is_vip'] ?? data['isVip'] ?? data['vip'];

      if (rawVip is bool) return rawVip;
      if (rawVip is String) return rawVip.toLowerCase() == 'true';
      return false;
    } catch (_) {
      return null;
    }
  }
}
