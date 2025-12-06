import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/notifications/models/notification_event.dart';

/// Helper para traduzir mensagens de notificação baseadas em tipo semântico
/// 
/// ✅ BEST PRACTICE: Tradução no cliente, baseada em tipos semânticos
/// ❌ ANTI-PATTERN: Mensagens hardcoded no banco de dados
class NotificationMessageTranslator {
  /// Traduz uma mensagem de notificação baseada no tipo e parâmetros
  /// 
  /// Esta é a forma recomendada: recebe tipo semântico + parâmetros,
  /// retorna mensagem formatada no idioma do usuário.
  static String translate({
    required AppLocalizations i18n,
    required String type,
    String? senderName,
    Map<String, dynamic>? params,
  }) {
    // Extrair senderName dos parâmetros se não fornecido diretamente
    senderName ??= (params?['senderName'] as String?) ?? 
                   i18n.translate('someone');

    // ✅ Handle masked_someone key from backend
    if (senderName == 'masked_someone') {
      senderName = i18n.translate('masked_someone');
    }

    // Se não houver tipo, retornar mensagem padrão
    if (type.isEmpty) {
      return i18n.translate('notification_default');
    }

    // Extrair parâmetros comuns
    var messagePreview = params?['messagePreview'] as String? ?? 
                         params?['message'] as String? ?? '';

    // ✅ Check if messagePreview is a translation key (for automated messages)
    if (messagePreview.isNotEmpty && !messagePreview.contains(' ')) {
       final translatedPreview = i18n.translate(messagePreview);
       if (translatedPreview.isNotEmpty) {
          // Interpolate params into the preview
          messagePreview = _interpolate(translatedPreview, {
             'sender': senderName,
             'senderName': senderName,
             ...?params,
          });
       }
    }

    // Mapear tipo para chave de tradução
    String translationKey;
    switch (type) {
      case NOTIF_TYPE_MESSAGE:
      case 'new_message':
        translationKey = 'notification_message';
      
      // Notificações de atividades
      case 'activity_created':
        translationKey = 'notification_activity_created';
      
      case 'activity_join_request':
        translationKey = 'notification_activity_join_request';
      
      case 'activity_join_approved':
        translationKey = 'notification_activity_join_approved';
      
      case 'activity_join_rejected':
        translationKey = 'notification_activity_join_rejected';
      
      case 'activity_new_participant':
        translationKey = 'notification_activity_new_participant';
      
      case 'activity_heating_up':
        translationKey = 'notification_activity_heating_up';
      
      case 'activity_expiring_soon':
        translationKey = 'notification_activity_expiring_soon';
      
      case 'activity_canceled':
        translationKey = 'notification_activity_canceled';
      
      case 'event_chat_message':
        translationKey = 'notification_event_chat_message';
      
      case 'profile_views_aggregated':
        translationKey = 'notification_profile_views_aggregated';
      
      case 'alert':
        // Alertas podem ter mensagem customizada nos parâmetros
        final customMessage = params?['message'] as String?;
        if (customMessage != null && customMessage.isNotEmpty) {
          return customMessage;
        }
        translationKey = 'notification_alert';
      
      case 'custom':
        // Tipo customizado - tentar buscar key específica ou usar mensagem dos params
        final customKey = params?['translationKey'] as String?;
        if (customKey != null && customKey.isNotEmpty) {
          translationKey = customKey;
        } else {
          final customMessage = params?['message'] as String?;
          if (customMessage != null && customMessage.isNotEmpty) {
            return customMessage;
          }
          translationKey = 'notification_default';
        }
      
      default:
        // Tipo desconhecido, retornar mensagem genérica
        return i18n.translate('notification_default');
    }

    // Buscar template de tradução
    var template = i18n.translate(translationKey);
    
    // Substituir placeholders usando interpolação segura
    template = _interpolate(template, {
      ...?params, // Merge parâmetros brutos primeiro
      'sender': senderName,
      'senderName': senderName,
      'message': messagePreview,
      'messagePreview': messagePreview,
    });
    
    return template;
  }

  /// Traduz usando NotificationEvent (type-safe)
  static String translateFromEvent({
    required AppLocalizations i18n,
    required NotificationEvent event,
  }) {
    return translate(
      i18n: i18n,
      type: event.type.value,
      senderName: event.senderName,
      params: event.params,
    );
  }

  /// Interpola placeholders em um template
  /// 
  /// Suporta formatos: {key}, {{{key}}}, {{key}}
  static String _interpolate(String template, Map<String, dynamic> values) {
    var result = template;
    
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value?.toString() ?? '';
      
      // Substituir diferentes formatos de placeholder
      result = result.replaceAll('{$key}', value);
      result = result.replaceAll('{{$key}}', value);
      result = result.replaceAll('{{{$key}}}', value);
    }
    
    return result;
  }

  /// Extrai parâmetros de um documento de notificação do Firestore
  /// 
  /// Suporta tanto o novo formato (n_params) quanto o legado (n_metadata)
  static Map<String, dynamic>? extractParams(Map<String, dynamic> notificationData) {
    // Tentar n_params primeiro (novo formato)
    if (notificationData.containsKey(N_PARAMS)) {
      final params = notificationData[N_PARAMS];
      if (params is Map<String, dynamic>) {
        return params;
      }
    }

    // Fallback: n_metadata (formato de transição)
    if (notificationData.containsKey(N_METADATA)) {
      final metadata = notificationData[N_METADATA];
      if (metadata is Map<String, dynamic>) {
        return metadata;
      }
    }

    // Fallback: tentar extrair de campos diretos (formato muito legado)
    final extracted = <String, dynamic>{};
    
    // Lista de campos conhecidos que podem ser parâmetros
    const knownParamFields = [
      'message', 'messagePreview',
    ];
    
    for (final field in knownParamFields) {
      if (notificationData.containsKey(field)) {
        extracted[field] = notificationData[field];
      }
    }
    
    return extracted.isNotEmpty ? extracted : null;
  }

  /// Helper para extrair nome do sender de dados de notificação
  static String? extractSenderName(Map<String, dynamic> notificationData) {
    return (notificationData[N_SENDER_FULLNAME] as String?) ??
           (notificationData['sender_name'] as String?) ??
           (notificationData['n_sender_name'] as String?);
  }

  /// Helper para extrair tipo de notificação
  static String? extractType(Map<String, dynamic> notificationData) {
    return (notificationData[N_TYPE] as String?) ??
           (notificationData['type'] as String?);
  }
}
