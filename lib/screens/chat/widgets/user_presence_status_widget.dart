import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/models/user_model.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

class UserPresenceStatusWidget extends StatefulWidget {

  const UserPresenceStatusWidget({
    required this.userId, 
    required this.chatService, 
    super.key,
    this.isEvent = false,
    this.eventId,
  });
  final String userId;
  final ChatService chatService;
  final bool isEvent;
  final String? eventId;

  @override
  State<UserPresenceStatusWidget> createState() => _UserPresenceStatusWidgetState();
}

class _UserPresenceStatusWidgetState extends State<UserPresenceStatusWidget> {

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Para eventos, retorna apenas o activityText da coleção events
    if (widget.isEvent && widget.eventId != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const SizedBox();
          }
          
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final activityText = data?['activityText'] ?? data?['activity_text'] ?? '';
          
          if (activityText.isEmpty) return const SizedBox();
          
          return Text(
            activityText,
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
            overflow: TextOverflow.ellipsis,
          );
        },
      );
    }
    
    // Para usuários normais, mantém a lógica original
    return StreamBuilder<UserModel>(
      stream: widget.chatService.getUserUpdates(widget.userId),
      builder: (context, snapshot) {
        // Check data
        if (!snapshot.hasData) return const SizedBox();

        // Get user presence status
        final user = snapshot.data!;

        // Check user presence status
        if (user.isOnline ?? false) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                i18n.translate('ONLINE'),
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: GlimpseColors.textSubTitle,
                ),
              ),
            ],
          );
        }
        
        // Verificar último login
        final lastLogin = user.lastLogin;
        if (lastLogin == null) {
          return Text(
            i18n.translate('offline'),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
            overflow: TextOverflow.ellipsis,
          );
        }

        // Usar TimeAgoHelper com i18n
        final timeAgoText = TimeAgoHelper.format(context, timestamp: lastLogin);

        // Exibir texto sem hífen
        return Text(
          "${i18n.translate('last_seen')} $timeAgoText",
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: GlimpseColors.textSubTitle,
          ),
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
