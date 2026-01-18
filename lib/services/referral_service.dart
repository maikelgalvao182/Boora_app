import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReferralService {
  ReferralService._internal();

  static final ReferralService instance = ReferralService._internal();

  static const String _pendingReferrerIdKey = 'pending_referrer_id';
  static const String _pendingDeepLinkValueKey = 'pending_deep_link_value';
  static const String _pendingCapturedAtKey = 'pending_referral_captured_at';

  Future<void> captureReferral({
    required String referrerId,
    String? deepLinkValue,
  }) async {
    if (referrerId.trim().isEmpty) return;
    if (AppState.isLoggedIn) return;

    if (deepLinkValue != null &&
        deepLinkValue.isNotEmpty &&
        deepLinkValue != REFERRAL_DEEP_LINK_VALUE) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_pendingReferrerIdKey)) {
      return;
    }

    await prefs.setString(_pendingReferrerIdKey, referrerId);
    if (deepLinkValue != null && deepLinkValue.isNotEmpty) {
      await prefs.setString(_pendingDeepLinkValueKey, deepLinkValue);
    }
    await prefs.setInt(_pendingCapturedAtKey, DateTime.now().millisecondsSinceEpoch);

    AppLogger.info(
      'Referral capturado: $referrerId (deep_link_value=$deepLinkValue)',
      tag: 'REFERRAL',
    );
  }

  Future<String?> consumePendingReferrerId() async {
    final prefs = await SharedPreferences.getInstance();
    final referrerId = prefs.getString(_pendingReferrerIdKey);

    if (referrerId == null || referrerId.trim().isEmpty) {
      return null;
    }

    await prefs.remove(_pendingReferrerIdKey);
    await prefs.remove(_pendingDeepLinkValueKey);
    await prefs.remove(_pendingCapturedAtKey);

    AppLogger.info(
      'Referral consumido: $referrerId',
      tag: 'REFERRAL',
    );

    return referrerId;
  }

  String buildInviteLink({
    required String referrerId,
    String deepLinkValue = REFERRAL_DEEP_LINK_VALUE,
  }) {
    final baseUri = Uri.parse(
      'https://$APPSFLYER_ONELINK_DOMAIN/$APPSFLYER_ONELINK_TEMPLATE_ID',
    );

    final params = <String, String>{
      'pid': 'af_app_invites',
      'c': 'user_invite',
      'deep_link_value': deepLinkValue,
      'deep_link_sub2': referrerId,
      'af_sub1': referrerId,
      'af_dp': '$APPSFLYER_URI_SCHEME://main',
    };

    return baseUri.replace(queryParameters: params).toString();
  }

  String? buildInviteLinkForCurrentUser({
    String deepLinkValue = REFERRAL_DEEP_LINK_VALUE,
  }) {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) return null;

    return buildInviteLink(
      referrerId: userId,
      deepLinkValue: deepLinkValue,
    );
  }
}
