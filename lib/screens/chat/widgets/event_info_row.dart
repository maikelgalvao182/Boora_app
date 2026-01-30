import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/screens/chat/controllers/chat_app_bar_controller.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:partiu/shared/widgets/stacked_avatars.dart';

/// Linha com avatares empilhados, contador de membros e schedule
class EventInfoRow extends StatelessWidget {
  const EventInfoRow({
    required this.user,
    required this.chatService,
    required this.controller,
    super.key,
  });

  final User user;
  final ChatService chatService;
  final ChatAppBarController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chatService.getConversationSummary(user.userId),
      builder: (context, snap) {
        String scheduleText = '';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          scheduleText = ChatAppBarController.formatSchedule(data['schedule']);
        }
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatares empilhados com contador
            StackedAvatars(
              eventId: controller.eventId,
              avatarSize: 18,
              maxVisible: 3,
              showMemberCount: true,
              textStyle: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: GlimpseColors.textSubTitle,
              ),
            ),
            
            // Separador e data
            if (scheduleText.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '·',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textSubTitle,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  scheduleText,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textSubTitle,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
