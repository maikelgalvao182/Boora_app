// lib/features/notifications/templates/notification_templates.dart

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
  static String formatInterests(List<String> interests) {
    if (interests.isEmpty) return "";
    if (interests.length == 1) return interests.first;
    if (interests.length == 2) {
      return "${interests[0]} e ${interests[1]}";
    }
    return "${interests.take(2).join(', ')} e mais ${interests.length - 2}";
  }

  // --------------------------------------------------
  //  TEMPLATE 1: Atividade criada no raio do usuário
  // --------------------------------------------------
  /// Formato: "{activityName} {emoji}" no topo
  /// Mensagem: "{creatorName} criou esta atividade. Vai participar?"
  static NotificationMessage activityCreated({
    required String creatorName,
    required String activityName,
    required String emoji,
    List<String> commonInterests = const [],
  }) {
    final interestsText = commonInterests.isNotEmpty 
        ? " • Interesses em comum: ${formatInterests(commonInterests)}" 
        : "";

    return NotificationMessage(
      title: "$activityName $emoji",
      body: "$creatorName criou esta atividade. Vai participar?$interestsText",
      preview: "$creatorName criou uma nova atividade",
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
    required String requesterName,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: "$requesterName pediu para entrar na sua atividade",
      preview: "Novo pedido de entrada",
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 3: Entrada aprovada na atividade privada
  // --------------------------------------------------
  /// Texto atual: "Você foi aprovado para participar!"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityJoinApproved({
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: "Você foi aprovado para participar!",
      preview: "Entrada aprovada 🎉",
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 4: Entrada recusada na atividade privada
  // --------------------------------------------------
  /// Texto atual: "Seu pedido para entrar foi recusado"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityJoinRejected({
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: "Seu pedido para entrar foi recusado",
      preview: "Pedido recusado",
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 5: Novo participante entrou (atividade aberta)
  // --------------------------------------------------
  /// Texto atual: "{participantName} entrou na sua atividade!"
  /// Título: "{activityName} {emoji}"
  static NotificationMessage activityNewParticipant({
    required String participantName,
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: "$participantName entrou na sua atividade!",
      preview: "$participantName entrou",
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
    required String activityName,
    required String emoji,
    required String creatorName,
    required int participantCount,
  }) {
    return NotificationMessage(
      title: "🔥 Atividade bombando!",
      body: "As pessoas estão participando da atividade de $creatorName! Não fique de fora!",
      preview: "Atividade bombando 🔥",
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
    required String activityName,
    required String emoji,
    required int hoursRemaining,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: "Esta atividade está quase acabando. Última chance!",
      preview: "Atividade quase expirando ⏰",
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
    required String activityName,
    required String emoji,
  }) {
    return NotificationMessage(
      title: "$activityName $emoji",
      body: "Esta atividade foi cancelada",
      preview: "Atividade cancelada 🚫",
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 9: Nova mensagem no chat
  // --------------------------------------------------
  /// Para mensagens do chat
  static NotificationMessage newMessage({
    required String senderName,
    String? messagePreview,
  }) {
    final body = messagePreview != null && messagePreview.isNotEmpty
        ? "$senderName: $messagePreview"
        : "$senderName enviou uma mensagem";

    return NotificationMessage(
      title: "Nova mensagem",
      body: body,
      preview: "Nova mensagem de $senderName",
      extra: {
        if (messagePreview != null) 'messagePreview': messagePreview,
      },
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 10: Alerta do sistema
  // --------------------------------------------------
  /// Para alertas gerais do sistema
  static NotificationMessage systemAlert({
    required String message,
    String? title,
  }) {
    return NotificationMessage(
      title: title ?? "Partiu",
      body: message,
      preview: message.length > 50 ? "${message.substring(0, 47)}..." : message,
      extra: {},
    );
  }

  // --------------------------------------------------
  //  TEMPLATE 11: Notificação customizada
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
}
