import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/models/device_identity.dart';

class DeviceRepository {
  DeviceRepository({FirebaseFunctions? functions, FirebaseAuth? auth})
      : _functions = functions ?? FirebaseFunctions.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<DeviceBlacklistCheckResult> checkDeviceBlacklist(
    DeviceIdentityPayload payload,
  ) async {
    final result = await _functions
        .httpsCallable('checkDeviceBlacklist')
        .call(payload.toMap());

    final data = result.data as Map<dynamic, dynamic>? ?? {};
    final blocked = data['blocked'] == true;
    final reason = data['reason'] as String?;

    return DeviceBlacklistCheckResult(blocked: blocked, reason: reason);
  }

  Future<void> registerDevice(DeviceIdentityPayload payload) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be authenticated to register device');
    }

    final data = {
      ...payload.toMap(),
      'uid': user.uid,
    };

    await _functions.httpsCallable('registerDevice').call(data);
  }
}
