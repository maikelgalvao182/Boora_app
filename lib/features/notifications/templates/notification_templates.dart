// lib/features/notifications/templates/notification_templates.dart

import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Mensagem estruturada de notificação com title, body, preview e extras
class NotificationMessage {
  /// Título da notificação (geralmente o nome da atividade + emoji)
  final String title;
  
  /// Corpo da notificação (mensagem principal)
  final String body;
  
  /// Preview curto para lista de notificações
  final String preview;
  
  /// Dados extras para uso no app
  final Map<String, dynamic> extra;

  const NotificationMessage({
    required this.title,
    required this.body,
    required this.preview,
    this.extra = const {},
  });
  
  /// Converte para Map para envio ao Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'preview': preview,
      if (extra.isNotEmpty) 'extra': extra,
    };
  }
}

/// Engine de templates para padronizar TODAS as notificações do Partiu
/// 
/// ✅ Benefícios:
/// - Padronização total de texto
/// - Fácil internacionalização futura
/// - Triggers só enviam dados, não montam texto
/// - Preview + title + body sempre consistentes
class NotificationTemplates {
  // ---------------------------
  //  HELPER: formata lista de interesses
  // ---------------------------
  static String formatInterests({
    required AppLocalizations i18n,
    required List<String> interests,
  }) {
    if (interests.isEmpty) return '';
    if (interests.length == 1) return interests.first;
    if (interests.length == 2) {
      return i18n
          .translate('notification_interests_two')
          .replaceAll('{first}', interests[0])
          .replaceAll('{second}', interests[1]);
    }

    return i18n
        .translate('notification_interests_more')
        .replaceAll('{firstTwo}', interests.take(2).join(', '))
        .replaceAll('{remaining}', (interests.length - 2).toString());
  }

  // --------------------------------------------------
  //  TEMPLATE 1: Atividade criada no raio do usuário
  // --------------------------------------------------
  /// Formato: "{activityName} {emoji}" no topo
  /// Mensagem: "{creatorName} criou esta atividade. Vai participar?"
  static NotificationMessage activityCreated({
    required AppLocalizations i18n,
    required String creatorName,
    required String activityName,
    required String emoji,
    List<String> commonInterests = const [],
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n
          .translate('notification_template_activity_created_body')
          .replaceAll('{creatorName}', creatorName)
          .replaceAll('{activityName}', activityName),
      preview: i18n
          .translate('notification_template_activity_created_preview')
          .replaceAll('{creatorName}', creatorName),
      extra: {
        'commonInterests': commonInterests,
        'emoji': emoji,
        'activityName': activityName,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 2: Pedido para entrar na atividade privada
  // --------------------------------------------------
  /// Texto atual: "{requesterName} pediu para entrar na sua atividade"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityJoinRequest({
    required AppLocalizations i18n,
    required String requesterName,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n
          .translate('notification_template_activity_join_request_body')
          .replaceAll('{requesterName}', requesterName),
      preview: i18n.translate('notification_template_activity_join_request_preview'),
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 3: Entrada aprovada na atividade privada
  // --------------------------------------------------
  /// Texto atual: "Você foi aprovado para participar!"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityJoinApproved({
    required AppLocalizations i18n,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n.translate('notification_template_activity_join_approved_body'),
      preview: i18n.translate('notification_template_activity_join_approved_preview'),
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 4: Entrada recusada na atividade privada
  // --------------------------------------------------
  /// Texto atual: "Seu pedido para entrar foi recusado"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityJoinRejected({
    required AppLocalizations i18n,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n.translate('notification_template_activity_join_rejected_body'),
      preview: i18n.translate('notification_template_activity_join_rejected_preview'),
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 5: Novo participante entrou (atividade aberta)
  // --------------------------------------------------
  /// Texto atual: "{participantName} entrou na sua atividade!"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityNewParticipant({
    required AppLocalizations i18n,
    required String participantName,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n
          .translate('notification_template_activity_new_participant_body')
          .replaceAll('{participantName}', participantName),
      preview: i18n
          .translate('notification_template_activity_new_participant_preview')
          .replaceAll('{participantName}', participantName),
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 6: Atividade esquentando (threshold de pessoas)
  // --------------------------------------------------
  /// Texto linha 1: "Atividade bombando! Não fique de fora"
  /// Texto linha 2: "As pessoas estão participando da atividade de {creatorName}! Não fique de fora!"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityHeatingUp({
    required AppLocalizations i18n,
    required String activityName,
    required String emoji,
    required String creatorName,
    required int participantCount,
  }) {
    return NotificationMessage(
      title: i18n.translate('notification_template_activity_heating_up_title'),
      body: i18n
          .translate('notification_template_activity_heating_up_body')
          .replaceAll('{creatorName}', creatorName),
      preview: i18n.translate('notification_template_activity_heating_up_preview'),
      extra: {
        'participantCount': participantCount,
        'activityName': activityName,
        'emoji': emoji,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 7: Atividade quase expirando
  // --------------------------------------------------
  /// Texto atual: "Esta atividade está quase acabando. Última chance!"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityExpiringSoon({
    required AppLocalizations i18n,
    required String activityName,
    required String emoji,
    required int hoursRemaining,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n.translate('notification_template_activity_expiring_soon_body'),
      preview: i18n.translate('notification_template_activity_expiring_soon_preview'),
      extra: {
        'hoursRemaining': hoursRemaining,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 8: Atividade cancelada
  // --------------------------------------------------
  /// Texto atual: "Esta atividade foi cancelada"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityCanceled({
    required AppLocalizations i18n,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: i18n.translate('notification_template_activity_canceled_body'),
      preview: i18n.translate('notification_template_activity_canceled_preview'),
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 9: Nova mensagem no chat
  // --------------------------------------------------
  /// Para mensagens 1-1 do chat privado
  /// 
  /// IMPORTANTE: Esta notificação é APENAS para push notification (FCM)
  /// NÃO deve ser salva na coleção Notifications (in-app)
  static NotificationMessage newMessage({
    required AppLocalizations i18n,
    required String senderName,
    String? messagePreview,
  }) {
    final body = messagePreview != null && messagePreview.isNotEmpty
        ? i18n
            .translate('notification_template_new_message_body_with_preview')
            .replaceAll('{senderName}', senderName)
            .replaceAll('{messagePreview}', messagePreview)
        : i18n
            .translate('notification_template_new_message_body')
            .replaceAll('{senderName}', senderName);

    return NotificationMessage(
      title: i18n.translate('notification_template_new_message_title'),
      body: body,
      preview: i18n
          .translate('notification_template_new_message_preview')
          .replaceAll('{senderName}', senderName),
      extra: {
        if (messagePreview != null) 'messagePreview': messagePreview,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 10: Nova mensagem no chat de evento
  // --------------------------------------------------
  /// Para mensagens do EventChat (grupo)
  /// 
  /// IMPORTANTE: Esta notificação é APENAS para push notification (FCM)
  /// NÃO deve ser salva na coleção Notifications (in-app)
  static NotificationMessage eventChatMessage({
    required AppLocalizations i18n,
    required String senderName,
    required String eventName,
    required String emoji,
    String? messagePreview,
  }) {
    final body = messagePreview != null && messagePreview.isNotEmpty
        ? i18n
            .translate('notification_template_new_message_body_with_preview')
            .replaceAll('{senderName}', senderName)
            .replaceAll('{messagePreview}', messagePreview)
        : i18n
            .translate('notification_template_new_message_body')
            .replaceAll('{senderName}', senderName);

    return NotificationMessage(
      title: "$eventName $emoji",
      body: body,
      preview: i18n
          .translate('notification_template_event_chat_message_preview')
          .replaceAll('{senderName}', senderName),
      extra: {
        if (messagePreview != null) 'messagePreview': messagePreview,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 11: Visualizações de perfil agregadas
  // --------------------------------------------------
  /// Notificação agregada de visualizações de perfil
  /// Disparada pela Cloud Function a cada 15 minutos
  /// 
  /// Título (negrito): contador de visualizações
  /// Body: "Novos amigos?" (call-to-action)
  /// Emoji do avatar: 👀 (eyes)
  /// 
  /// Exemplos de título:
  /// - "1 pessoa visualizou seu perfil 👏"
  /// - "5 pessoas visualizaram seu perfil 👏"
  static NotificationMessage profileViewsAggregated({
    required AppLocalizations i18n,
    required int count,
    String? lastViewedAt,
    List<String>? viewerNames,
  }) {
    final title = count == 1
        ? i18n.translate('notification_template_profile_views_title_singular')
        : i18n
            .translate('notification_template_profile_views_title_plural')
            .replaceAll('{count}', count.toString());

    final preview = count == 1
        ? i18n.translate('notification_template_profile_views_preview_singular').replaceAll('{count}', count.toString())
        : i18n.translate('notification_template_profile_views_preview_plural').replaceAll('{count}', count.toString());

    return NotificationMessage(
      title: title,
      body: i18n.translate('notification_template_profile_views_body'),
      preview: preview,
      extra: {
        'count': count,
        'emoji': '👀', // Emoji para o avatar da notificação
        if (viewerNames != null) 'viewerNames': viewerNames,
        if (lastViewedAt != null) 'lastViewedAt': lastViewedAt,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 12: Alerta do sistema
  // --------------------------------------------------
  /// Para alertas gerais do sistema
  static NotificationMessage systemAlert({
    required String message,
    String? title,
  }) {
    return NotificationMessage(
      title: title ?? APP_NAME,
      body: message,
      preview: message.length > 50 ? "${message.substring(0, 47)}..." : message,
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 13: Notificação customizada
  // --------------------------------------------------
  /// Para casos especiais que não se encaixam nos templates acima
  static NotificationMessage custom({
    required String title,
    required String body,
    String? preview,
    Map<String, dynamic> extra = const {},
  }) {
    return NotificationMessage(
      title: title,
      body: body,
      preview: preview ?? (body.length > 50 ? "${body.substring(0, 47)}..." : body),
      extra: extra,
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 14: Novo seguidor
  // --------------------------------------------------
  /// Notificação quando alguém começa a seguir o usuário
  /// 
  /// Título (negrito): "{followerName} começou a te seguir"
  /// Body: "Toque para ver o perfil"
  /// Avatar: foto do seguidor
  /// Deep link: partiu://profile/{followerId}
  static NotificationMessage newFollower({
    required AppLocalizations i18n,
    required String followerName,
    required String followerId,
  }) {
    return NotificationMessage(
      title: i18n
          .translate('notification_template_new_follower_title')
          .replaceAll('{followerName}', followerName),
      body: i18n.translate('notification_template_new_follower_body'),
      preview: i18n
          .translate('notification_template_new_follower_preview')
          .replaceAll('{followerName}', followerName),
      extra: {
        'followerId': followerId,
        'deepLink': 'partiu://profile/$followerId',
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 15: Nova avaliação recebida
  // --------------------------------------------------
  /// Texto: "{reviewerName} avaliou você!"
  /// Título: "Nova avaliação ⭐️"
  static NotificationMessage newReviewReceived({
    required AppLocalizations i18n,
    required String reviewerName,
    required double rating,
    String? comment,
  }) {
    final body = comment != null && comment.isNotEmpty
        ? i18n
            .translate('notification_template_new_review_received_body_with_comment')
            .replaceAll('{reviewerName}', reviewerName)
            .replaceAll('{comment}', comment)
        : i18n
            .translate('notification_template_new_review_received_body')
            .replaceAll('{reviewerName}', reviewerName)
            .replaceAll('{rating}', rating.toStringAsFixed(1));

    return NotificationMessage(
      title: i18n.translate('notification_template_new_review_received_title'),
      body: body,
      preview: i18n.translate('notification_template_new_review_received_preview'),
      extra: {
        'rating': rating,
      },
    );
  }
}
