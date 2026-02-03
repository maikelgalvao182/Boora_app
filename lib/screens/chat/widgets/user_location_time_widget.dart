import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Widget que exibe localização (locality, state) e time ago do usuário
/// Usado no ChatAppBar para chats 1x1
class UserLocationTimeWidget extends StatelessWidget {
  const UserLocationTimeWidget({
    required this.user,
    super.key,
    this.showTime = true,
    this.conversationData,
  });

  final User user;
  final bool showTime;
  final Map<String, dynamic>? conversationData;

  @override
  Widget build(BuildContext context) {
    final cityNotifier = UserStore.instance.getCityNotifier(user.userId);
    final stateNotifier = UserStore.instance.getStateNotifier(user.userId);
    final lastMessageTime = _extractLastMessageTime(conversationData);

    return ValueListenableBuilder<String?>(
      valueListenable: cityNotifier,
      builder: (context, city, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: stateNotifier,
          builder: (context, state, __) {
            final locality = city ?? user.userLocality;
            final stateStr = state ?? user.userState ?? '';
            return _buildRow(locality, stateStr, lastMessageTime);
          },
        );
      },
    );
  }

  DateTime? _extractLastMessageTime(Map<String, dynamic>? data) {
    if (data == null) return null;

    final timestampValue = data['last_message_timestamp']
        ?? data['last_message_at']
        ?? data['lastMessageAt']
        ?? data['timestamp'];

    if (timestampValue == null) return null;
    if (timestampValue is Timestamp) return timestampValue.toDate();
    if (timestampValue is DateTime) return timestampValue;
    if (timestampValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestampValue);
    }
    if (timestampValue is num) {
      return DateTime.fromMillisecondsSinceEpoch(timestampValue.toInt());
    }
    return null;
  }

  /// Constrói a row com localização e time ago
  Widget _buildRow(String locality, String state, DateTime? lastMessageTime) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Locality, State
        Flexible(
          child: _buildLocationText(locality, state),
        ),
        if (showTime) ...[
          const SizedBox(width: 8),
          // Last message time ago
          _buildLastMessageTimeText(lastMessageTime),
        ],
      ],
    );
  }

  /// Widget de localização
  Widget _buildLocationText(String locality, String state) {
    String locationText = '';
    if (locality.isNotEmpty && state.isNotEmpty) {
      locationText = '$locality, $state';
    } else if (locality.isNotEmpty) {
      locationText = locality;
    } else if (state.isNotEmpty) {
      locationText = state;
    }

    if (locationText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      locationText,
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: 12,
        color: GlimpseColors.textSubTitle,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Widget de last seen - Reativo usando o lastLogin já disponível
  /// Widget de time ago da última mensagem (igual ao conversation_tile.dart)
  Widget _buildLastMessageTimeText(DateTime? lastMessageTime) {
    if (lastMessageTime == null) {
      return const SizedBox.shrink();
    }
    
    return Builder(
      builder: (context) {
        final timeAgoText = TimeAgoHelper.format(
          context,
          timestamp: lastMessageTime,
        );
        if (timeAgoText.isEmpty) {
          return const SizedBox.shrink();
        }
        return Text(
          timeAgoText,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 11,
            color: GlimpseColors.textSubTitle,
          ),
        );
      },
    );
  }
}
