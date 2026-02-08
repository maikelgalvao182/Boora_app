import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:partiu/shared/widgets/pending_participants_stack.dart';

/// Step de comentário opcional (Step 2)
class CommentStep extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<Map<String, String>> remainingParticipants;

  const CommentStep({
    required this.controller,
    this.focusNode,
    this.remainingParticipants = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Campo de texto
        GlimpseTextField(
          controller: controller,
          focusNode: focusNode,
          hintText: i18n.translate('review_comment_hint'),
          maxLines: 6,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
        ),
        
        if (remainingParticipants.isNotEmpty) ...[
          SizedBox(height: 16.h),
          PendingParticipantsStack(
            participants: remainingParticipants,
          ),
        ],
      ],
    );
  }
}
