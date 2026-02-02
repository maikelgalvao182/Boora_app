import 'dart:convert';

import 'package:client_information/client_information.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/models/device_identity.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/shared/repositories/device_repository.dart';

class DeviceIdentityService {
  DeviceIdentityService._({DeviceRepository? repository, FirebaseAuth? auth})
      : _repository = repository ?? DeviceRepository(),
        _auth = auth ?? FirebaseAuth.instance;

  static final DeviceIdentityService instance = DeviceIdentityService._();

  final DeviceRepository _repository;
  final FirebaseAuth _auth;

  static const String _tag = 'DeviceIdentityService';

  Future<DeviceBlacklistCheckResult> checkDeviceBlacklist() async {
    final payload = await _collectIdentity();
    if (payload == null) {
      AppLogger.warning(
        'Device identity unavailable, skipping blacklist check',
        tag: _tag,
      );
      return DeviceBlacklistCheckResult(blocked: false);
    }

    return _repository.checkDeviceBlacklist(payload);
  }

  Future<void> registerDevice() async {
    final payload = await _collectIdentity();
    if (payload == null) {
      AppLogger.warning(
        'Device identity unavailable, skipping registerDevice',
        tag: _tag,
      );
      return;
    }

    await _repository.registerDevice(payload);
  }

  Future<DeviceBlacklistCheckResult> checkAndRegisterOnLogin() async {
    if (_auth.currentUser == null) {
      AppLogger.warning('User not authenticated, skipping register', tag: _tag);
      return DeviceBlacklistCheckResult(blocked: false);
    }

    final payload = await _collectIdentity();
    if (payload == null) {
      AppLogger.warning(
        'Device identity unavailable, skipping check/register',
        tag: _tag,
      );
      return DeviceBlacklistCheckResult(blocked: false);
    }

    final result = await _repository.checkDeviceBlacklist(payload);
    if (result.blocked) {
      return result;
    }

    await _repository.registerDevice(payload);
    return result;
  }

  Future<DeviceIdentityPayload?> _collectIdentity() async {
    try {
      final info = await ClientInformation.fetch();
      final rawDeviceId = (info.deviceId ?? '').trim();

      if (rawDeviceId.isEmpty) {
        AppLogger.warning('deviceId is empty', tag: _tag);
        return null;
      }

      final deviceIdHash = _hashDeviceId(rawDeviceId);
      final platform = _resolvePlatform();

      return DeviceIdentityPayload(
        deviceIdHash: deviceIdHash,
        platform: platform,
        deviceName: _sanitize(info.deviceName),
        osName: _sanitize(info.osName),
        osVersion: _sanitize(info.osVersion),
        appVersion: _sanitize(info.applicationVersion),
        buildCode: _sanitize(info.applicationBuildCode?.toString()),
        applicationName: _sanitize(info.applicationName),
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to collect device identity',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String _hashDeviceId(String rawDeviceId) {
    return sha256.convert(utf8.encode(rawDeviceId)).toString();
  }

  String _resolvePlatform() {
    if (kIsWeb) return 'web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String? _sanitize(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
