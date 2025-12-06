import 'package:partiu/core/utils/app_localizations.dart';

/// Model for pre-processed conversation display data
class ConversationDisplayData {
  const ConversationDisplayData({
    required this.photoUrl,
    required this.displayName,
    required this.fullName,
    required this.maskedName,
    required this.otherUserId,
    required this.lastMessage,
    required this.timeAgo,
    required this.isVip,
    required this.hasUnreadMessage,
    required this.messageType,
    required this.isVerified,
  });
  final String photoUrl;
  final String displayName;
  final String fullName;
  final String maskedName;
  final String otherUserId;
  final String lastMessage;
  final String timeAgo;
  final bool isVip;
  final bool hasUnreadMessage;
  final String messageType;
  final bool isVerified;
}

/// Service responsible for processing conversation data for display
class ConversationDataProcessor {
  static const int _maxMessageLength = 30;
  static const int _truncateLength = 30;

  /// Extract photo URL from conversation data with fallback chain
  static String extractPhotoUrl(Map<String, dynamic> data) {
    // Prioritize fields that typically have valid URLs
    final candidates = <dynamic>[
      data['profileImageURL'],
      data['emoji'],
      data['user_profile_photo'],
      data['photo_url'],
      data['user_photo_link'],
      data['user_photo'],
      data['profile_photo'],
      data['profile_photo_url'],
      data['avatar_url'],
      data['avatar'],
      data['photo'],
      data['image_url'],
      data['profile_image_url'],
    ];

    // First pass: find any non-empty string
    var rawUrl = '';
    for (final candidate in candidates) {
      if (candidate is String) {
        final trimmed = candidate.trim();
        if (trimmed.isNotEmpty) {
          rawUrl = trimmed;
          break;
        }
      }
    }

    if (rawUrl.isEmpty) {
      return '';
    }

    // Validate URL
    final isValid = _isValidImageUrl(rawUrl);

    return isValid ? rawUrl : '';
  }

  /// Extract verification status using multiple naming conventions
  static bool? _extractVerificationStatus(Map<String, dynamic> data) {
    final candidates = [
      data['user_is_verified'],
      data['is_verified'],
      data['userIsVerified'],
      data['isVerified'],
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (candidate is bool) {
        return candidate;
      }
      if (candidate is int) {
        if (candidate >= 1) return true;
        if (candidate == 0) return false;
      }
      if (candidate is String) {
        final lower = candidate.toLowerCase().trim();
        if (lower == 'true' || lower == '1' || lower == 'yes') return true;
        if (lower == 'false' || lower == '0' || lower == 'no') return false;
      }
    }

    return null;
  }

  /// Validate if URL is potentially valid for network loading
  static bool _isValidImageUrl(String url) {
    return url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://')) &&
        url.contains('.');
  }

  /// Process name for VIP masking based on user status
  static String processNameForDisplay({
    required String fullName,
    required bool isVip,
    required bool isVipEffective,
  }) {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) return '';

    final firstWord = trimmedName.split(' ').first;

    // TODO: Apply VIP masking logic if needed
    // For now, just return the first name
    return firstWord;
  }

  /// Format timestamp to relative time string
  static String formatTimeAgo({
    required dynamic timestamp,
    required String locale,
  }) {
    if (timestamp == null) return '';

    DateTime? dateTime;

    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is String) {
      dateTime = DateTime.tryParse(timestamp);
    } else if (timestamp is Map) {
      final seconds = timestamp['seconds'] ?? timestamp['_seconds'];
      if (seconds is int) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    if (dateTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '${years}a';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}m';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}min';
    } else {
      return 'agora';
    }
  }

  /// Truncate message for display
  static String truncateMessage(String message) {
    if (message.length <= _maxMessageLength) {
      return message;
    }
    return '${message.substring(0, _truncateLength)}...';
  }

  /// Get display message based on type
  static String getDisplayMessage({
    required Map<String, dynamic> data,
    required AppLocalizations i18n,
  }) {
    final messageType =
        (data['last_message_type'] ?? data['message_type'] ?? 'text')
            .toString();

    if (messageType == 'text' || messageType == 'user') {
      final rawMessage = (data['last_message'] ??
              data['last_message_text'] ??
              data['message_text'] ??
              data['lastMessageText'] ??
              data['lastMessage'] ??
              '')
          .toString();
      return truncateMessage(rawMessage);
    }

    if (messageType == 'automated') {
      final rawMessage = (data['last_message'] ??
              data['last_message_text'] ??
              data['message_text'] ??
              '')
          .toString();

      // Try to translate the key
      var translated = i18n.translate(rawMessage);

      // If translation exists
      if (translated.isNotEmpty) {
        // Get params for replacement
        final params = data['last_message_params'] ?? data['message_params'];

        if (params is Map) {
          params.forEach((key, value) {
            translated = translated.replaceAll('{$key}', value.toString());
          });
        }
        return truncateMessage(translated);
      }
      return truncateMessage(rawMessage);
    }

    return i18n.translate('photo');
  }

  /// Process all conversation data for display
  static Future<ConversationDisplayData> processConversationData({
    required Map<String, dynamic> data,
    required bool isVipEffective,
    required AppLocalizations i18n,
  }) async {
    final fullNameRaw = (data['activityText'] ??
            data['fullname'] ??
            data['other_user_name'] ??
            data['otherUserName'] ??
            data['user_name'] ??
            '')
        .toString()
        .trim();
    final photoUrl = extractPhotoUrl(data);
    // Para eventos, usar event_id. Para conversas normais, user_id
    final isEventChat = data['is_event_chat'] == true || data['event_id'] != null;
    final otherUserId = isEventChat 
        ? 'event_${data['event_id']}'
        : (data['user_id'] ??
            data['other_user_id'] ??
            data['otherUserId'] ??
            data['uid'] ??
            data['id'] ??
            '')
        .toString();
    final isVip = isVipEffective;

    final maskedName = processNameForDisplay(
      fullName: fullNameRaw,
      isVip: isVip,
      isVipEffective: isVipEffective,
    );

    final fullName = fullNameRaw.isNotEmpty ? fullNameRaw : maskedName;
    final lastMessage = getDisplayMessage(data: data, i18n: i18n);

    final timestampValue = data['last_message_timestamp'] ??
        data['last_message_at'] ??
        data['lastMessageAt'] ??
        data['timestamp'];
    final timeAgo = formatTimeAgo(
      timestamp: timestampValue,
      locale: i18n.translate('lang'),
    );

    // Consider both boolean flag and counter fields as sources of truth
    final dynamic readFlag = data['message_read'];
    final isUnreadByFlag = (readFlag is bool) ? (readFlag == false) : false;
    final unreadCount = _toIntSafe(data['unread_count']) ??
        _toIntSafe(data['unreadCount']) ??
        0;
    final hasUnreadMessage = isUnreadByFlag || unreadCount > 0;
    final messageType = (data['last_message_type'] ??
            data['message_type'] ??
            data['lastMessageType'] ??
            'text')
        .toString();

    // Extract verification status
    final isVerifiedExplicit = _extractVerificationStatus(data);

    // For now, if not found in conversation data, default to false
    // TODO: Implement async fetch from Users collection if needed
    var isVerified = isVerifiedExplicit ?? false;

    return ConversationDisplayData(
      photoUrl: photoUrl,
      displayName: maskedName,
      fullName: fullName,
      maskedName: maskedName,
      otherUserId: otherUserId,
      lastMessage: lastMessage,
      timeAgo: timeAgo,
      isVip: isVip,
      hasUnreadMessage: hasUnreadMessage,
      messageType: messageType,
      isVerified: isVerified,
    );
  }

  /// Synchronous portion of processing (excluding async verification fetch)
  static ConversationDisplayData processConversationDataSync({
    required Map<String, dynamic> data,
    required bool isVipEffective,
    required AppLocalizations i18n,
  }) {
    final fullNameRaw = (data['activityText'] ??
            data['fullname'] ??
            data['other_user_name'] ??
            data['otherUserName'] ??
            data['user_name'] ??
            '')
        .toString()
        .trim();
    final photoUrl = extractPhotoUrl(data);
    // Para eventos, usar event_id. Para conversas normais, user_id
    final isEventChat = data['is_event_chat'] == true || data['event_id'] != null;
    final otherUserId = isEventChat 
        ? 'event_${data['event_id']}'
        : (data['user_id'] ??
            data['other_user_id'] ??
            data['otherUserId'] ??
            data['uid'] ??
            data['id'] ??
            '')
        .toString();
    final isVip = isVipEffective;

    final maskedName = processNameForDisplay(
      fullName: fullNameRaw,
      isVip: isVip,
      isVipEffective: isVipEffective,
    );

    final fullName = fullNameRaw.isNotEmpty ? fullNameRaw : maskedName;
    final lastMessage = getDisplayMessage(data: data, i18n: i18n);

    final timestampValue = data['last_message_timestamp'] ??
        data['last_message_at'] ??
        data['lastMessageAt'] ??
        data['timestamp'];
    final timeAgo = formatTimeAgo(
      timestamp: timestampValue,
      locale: i18n.translate('lang'),
    );
    final dynamic readFlag2 = data['message_read'];
    final isUnreadByFlag2 = (readFlag2 is bool) ? (readFlag2 == false) : false;
    final unreadCount2 = _toIntSafe(data['unread_count']) ??
        _toIntSafe(data['unreadCount']) ??
        0;
    final hasUnreadMessage = isUnreadByFlag2 || unreadCount2 > 0;
    final messageType = (data['last_message_type'] ??
            data['message_type'] ??
            data['lastMessageType'] ??
            'text')
        .toString();

    // Extract verification status
    final isVerifiedExplicit = _extractVerificationStatus(data);
    final isVerified = isVerifiedExplicit ?? false;

    return ConversationDisplayData(
      photoUrl: photoUrl,
      displayName: maskedName,
      fullName: fullName,
      maskedName: maskedName,
      otherUserId: otherUserId,
      lastMessage: lastMessage,
      timeAgo: timeAgo,
      isVip: isVip,
      hasUnreadMessage: hasUnreadMessage,
      messageType: messageType,
      isVerified: isVerified,
    );
  }
}

int? _toIntSafe(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
