import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Widget reutilizável para o header de comentários e replies
/// Exibe: fullname (esquerda) | time ago (direita)
class CommentHeader extends StatelessWidget {
  const CommentHeader({
    super.key,
    required this.userId,
    this.createdAt,
  });

  final String userId;
  final Timestamp? createdAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Nome do usuário com badge (expande para ocupar espaço disponível)
        Expanded(
          child: ReactiveUserNameWithBadge(
            userId: userId,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
        ),
        // Time ago no canto direito
        if (createdAt != null) ...[
          const SizedBox(width: 8),
          Text(
            TimeAgoHelper.format(context, timestamp: createdAt!.toDate()),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      ],
    );
  }
}
