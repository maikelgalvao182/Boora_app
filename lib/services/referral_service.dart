import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/services/appsflyer_service.dart';
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
    AppLogger.info('📥 captureReferral chamado - referrerId: $referrerId, deepLinkValue: $deepLinkValue', tag: 'REFERRAL');
    
    if (referrerId.trim().isEmpty) {
      AppLogger.warning('⚠️ referrerId vazio, ignorando', tag: 'REFERRAL');
      return;
    }
    
    if (AppState.isLoggedIn) {
      AppLogger.warning('⚠️ Usuário já logado, ignorando captureReferral', tag: 'REFERRAL');
      return;
    }

    if (deepLinkValue != null &&
        deepLinkValue.isNotEmpty &&
        deepLinkValue != REFERRAL_DEEP_LINK_VALUE) {
      AppLogger.warning('⚠️ deepLinkValue diferente de invite: $deepLinkValue vs $REFERRAL_DEEP_LINK_VALUE', tag: 'REFERRAL');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_pendingReferrerIdKey)) {
      AppLogger.warning('⚠️ Já existe referral pendente, ignorando', tag: 'REFERRAL');
      return;
    }

    await prefs.setString(_pendingReferrerIdKey, referrerId);
    if (deepLinkValue != null && deepLinkValue.isNotEmpty) {
      await prefs.setString(_pendingDeepLinkValueKey, deepLinkValue);
    }
    await prefs.setInt(_pendingCapturedAtKey, DateTime.now().millisecondsSinceEpoch);

    AppLogger.success(
      '✅ Referral capturado e salvo: $referrerId (deep_link_value=$deepLinkValue)',
      tag: 'REFERRAL',
    );
  }

  Future<String?> consumePendingReferrerId() async {
    AppLogger.info('📤 consumePendingReferrerId chamado', tag: 'REFERRAL');
    
    final prefs = await SharedPreferences.getInstance();
    final referrerId = prefs.getString(_pendingReferrerIdKey);

    AppLogger.info('📤 Valor encontrado no SharedPreferences: $referrerId', tag: 'REFERRAL');

    if (referrerId == null || referrerId.trim().isEmpty) {
      AppLogger.warning('⚠️ Nenhum referral pendente encontrado', tag: 'REFERRAL');
      return null;
    }

    await prefs.remove(_pendingReferrerIdKey);
    await prefs.remove(_pendingDeepLinkValueKey);
    await prefs.remove(_pendingCapturedAtKey);

    AppLogger.success(
      '✅ Referral consumido: $referrerId',
      tag: 'REFERRAL',
    );

    return referrerId;
  }

  /// Gera link de convite usando a API oficial do AppsFlyer
  /// Retorna o link gerado ou null se falhar
  Future<String?> generateInviteLinkAsync({
    required String referrerId,
    String? referrerName,
  }) async {
    AppLogger.info('🔗 Gerando link de convite via AppsFlyer API para: $referrerId', tag: 'REFERRAL');

    // Evita race condition: em alguns boots a UI pede o link antes do AppsFlyer terminar o init.
    // Aqui esperamos um curto período para o init terminar antes de cair no fallback.
    if (!AppsflyerService.instance.isInitialized) {
      const maxWait = Duration(seconds: 3);
      const step = Duration(milliseconds: 150);
      var waited = Duration.zero;
      while (!AppsflyerService.instance.isInitialized && waited < maxWait) {
        await Future<void>.delayed(step);
        waited += step;
      }
      if (!AppsflyerService.instance.isInitialized) {
        AppLogger.warning(
          '⚠️ AppsFlyer ainda não inicializado após ${maxWait.inSeconds}s - usando fallback manual',
          tag: 'REFERRAL',
        );
      } else {
        AppLogger.info('✅ AppsFlyer inicializado após espera (${waited.inMilliseconds}ms)', tag: 'REFERRAL');
      }
    }
    
    final link = await AppsflyerService.instance.generateInviteLink(
      referrerId: referrerId,
      referrerName: referrerName,
      campaign: 'user_invite',
      channel: 'mobile_share',
    );

    if (link != null) {
      AppLogger.success('✅ Link de convite gerado: $link', tag: 'REFERRAL');
      return link;
    }

    // Fallback: gera link manualmente se a API falhar
    AppLogger.warning('⚠️ Fallback: gerando link manualmente', tag: 'REFERRAL');
    return buildInviteLink(referrerId: referrerId);
  }

  /// Gera link de convite para o usuário atual usando a API do AppsFlyer
  Future<String?> generateInviteLinkForCurrentUserAsync() async {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) {
      AppLogger.warning('⚠️ userId não disponível para gerar link', tag: 'REFERRAL');
      return null;
    }

    final userName = AppState.currentUser.value?.fullName;
    return generateInviteLinkAsync(
      referrerId: userId,
      referrerName: userName,
    );
  }

  /// Método síncrono (fallback) - constrói link manualmente
  /// Parâmetros conforme configurado no Dashboard AppsFlyer
  String buildInviteLink({
    required String referrerId,
    String deepLinkValue = REFERRAL_DEEP_LINK_VALUE,
  }) {
    final baseUri = Uri.parse(
      'https://$APPSFLYER_ONELINK_DOMAIN/$APPSFLYER_ONELINK_TEMPLATE_ID',
    );

    // Parâmetros conforme Dashboard:
    // pid = User_invite
    // c = Convite
    // deep_link_value = invite
    // deep_link_sub1 = new_member
    // deep_link_sub2 = referrerId
    final params = <String, String>{
      'pid': 'User_invite',           // Conforme dashboard
      'c': 'Convite',                  // Conforme dashboard
      'deep_link_value': deepLinkValue,
      'deep_link_sub1': 'new_member',  // Conforme dashboard
      'deep_link_sub2': referrerId,
      'af_sub1': referrerId,
      'af_dp': '$APPSFLYER_URI_SCHEME://main',
    };

    return baseUri.replace(queryParameters: params).toString();
  }

  /// Método síncrono (fallback) para o usuário atual
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
