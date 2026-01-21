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

  /// Gera link de convite para o usuário
  /// Retorna o link gerado ou null se falhar
  Future<String?> generateInviteLinkAsync({
    required String referrerId,
    String? referrerName,
  }) async {
    AppLogger.info('🔗 Gerando link de convite para: $referrerId', tag: 'REFERRAL');
    
    // Usa o método de fallback agora que AppsFlyer foi removido
    final link = buildInviteLink(referrerId: referrerId);
    AppLogger.success('✅ Link de convite gerado: $link', tag: 'REFERRAL');
    return link;
  }

  /// Gera link de convite para o usuário atual
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

  /// Método síncrono - constrói link de convite
  String buildInviteLink({
    required String referrerId,
    String deepLinkValue = REFERRAL_DEEP_LINK_VALUE,
  }) {
    // Link simples sem AppsFlyer - usa Firebase Dynamic Links ou link direto
    // Por enquanto usa link direto que pode ser processado pelo app
    final baseUri = Uri.parse('https://boora.app/invite');
    
    final params = <String, String>{
      'referrer': referrerId,
      'type': deepLinkValue,
    };

    return baseUri.replace(queryParameters: params).toString();
  }

  /// Método síncrono para o usuário atual
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
