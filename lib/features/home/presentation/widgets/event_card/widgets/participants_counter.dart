import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Widget reativo que exibe contador de participantes em formato chip
/// Usa Stream direto do Firestore - atualiza automaticamente
class ParticipantsCounter extends StatelessWidget {
  const ParticipantsCounter({
    required this.eventId,
    required this.singularLabel,
    required this.pluralLabel,
    super.key,
  });

  final String eventId;
  final String singularLabel;
  final String pluralLabel;

  /// Stream de contagem de participantes aprovados
  Stream<int> get _countStream {
    return FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: eventId)
        .where('status', whereIn: ['approved', 'autoApproved'])
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: GlimpseColors.primaryLight,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '$count ${count == 1 ? singularLabel : pluralLabel}',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
        );
      },
    );
  }
}
