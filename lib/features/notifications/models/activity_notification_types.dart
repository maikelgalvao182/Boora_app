/// Tipos específicos de notificações de atividades
/// 
/// Esta extensão adiciona tipos semânticos para eventos de atividades,
/// mantendo a arquitetura limpa e extensível do NotificationEvent.
library;

/// Tipos de notificação específicos para atividades
/// 
/// Valores das constantes correspondem aos tipos salvos no Firestore
/// e usados nas chaves de tradução (assets/lang/*.json)
class ActivityNotificationTypes {
  /// TRIGGER 1: Nova atividade criada no raio do usuário (30km)
  /// Chave i18n: 'notification_activity_created'
  /// Params: {activityText, emoji, creatorName}
  static const String activityCreated = 'activity_created';

  /// TRIGGER 2: Alguém pediu para entrar em atividade privada
  /// Chave i18n: 'notification_activity_join_request'
  /// Params: {activityText, emoji, requesterName}
  static const String activityJoinRequest = 'activity_join_request';

  /// TRIGGER 3: Dono aprovou entrada na atividade privada
  /// Chave i18n: 'notification_activity_join_approved'
  /// Params: {activityText, emoji}
  static const String activityJoinApproved = 'activity_join_approved';

  /// TRIGGER 4: Dono recusou entrada na atividade privada
  /// Chave i18n: 'notification_activity_join_rejected'
  /// Params: {activityText, emoji}
  static const String activityJoinRejected = 'activity_join_rejected';

  /// TRIGGER 5: Novo participante entrou em atividade aberta
  /// Chave i18n: 'notification_activity_new_participant'
  /// Params: {activityText, emoji, participantName}
  static const String activityNewParticipant = 'activity_new_participant';

  /// TRIGGER 6: Atividade atingiu threshold de participantes
  /// Chave i18n: 'notification_activity_heating_up'
  /// Params: {activityText, emoji, participantCount, creatorName}
  static const String activityHeatingUp = 'activity_heating_up';

  /// TRIGGER 7: Atividade próxima da expiração
  /// Chave i18n: 'notification_activity_expiring_soon'
  /// Params: {activityText, emoji, hoursRemaining}
  static const String activityExpiringSoon = 'activity_expiring_soon';

  /// TRIGGER 8: Atividade foi cancelada
  /// Chave i18n: 'notification_activity_canceled'
  /// Params: {activityText, emoji}
  static const String activityCanceled = 'activity_canceled';

  /// TRIGGER ESPECIAL: Visualizações de perfil agregadas
  /// Chave i18n: 'notification_profile_views_aggregated'
  /// Params: {count, lastViewedAt}
  static const String profileViewsAggregated = 'profile_views_aggregated';

  /// TRIGGER: Novo seguidor
  /// Chave i18n: 'notification_new_follower'
  /// Params: {followerName, followerId, deepLink}
  static const String newFollower = 'new_follower';

  /// Lista de todos os tipos de notificação de atividades
  static const List<String> all = [
    activityCreated,
    activityJoinRequest,
    activityJoinApproved,
    activityJoinRejected,
    activityNewParticipant,
    activityHeatingUp,
    activityExpiringSoon,
    activityCanceled,
    profileViewsAggregated,
    newFollower,
  ];

  /// Verifica se um tipo é de atividade
  static bool isActivityType(String type) => all.contains(type);

  /// Thresholds para trigger "heating up"
  static const List<int> heatingUpThresholds = [3, 5, 10];
}
