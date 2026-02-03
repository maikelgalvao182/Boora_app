import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';

/// Widget com ícone de denúncia e dialog para reportar eventos
class ReportEventButton extends StatelessWidget {
  const ReportEventButton({
    required this.eventId,
    super.key,
  });

  final String eventId;

  void _showReportDialog(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final barrierLabel = i18n.translate('dismiss');

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    constraints: const BoxConstraints(maxWidth: 500),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _ReportDialogContent(eventId: eventId),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          splashRadius: 18,
          icon: const Icon(
            IconsaxPlusLinear.warning_2,
            size: 20,
            color: GlimpseColors.error,
          ),
          onPressed: () => _showReportDialog(context),
        ),
      ),
    );
  }
}

class _ReportDialogContent extends StatefulWidget {
  const _ReportDialogContent({required this.eventId});

  final String eventId;

  @override
  State<_ReportDialogContent> createState() => _ReportDialogContentState();
}

class _ReportDialogContentState extends State<_ReportDialogContent> {
  final TextEditingController _reportController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Foca o campo automaticamente quando o dialog abre
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _reportController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitReport(BuildContext context) async {
    final i18n = AppLocalizations.of(context);
    final reportText = _reportController.text.trim();

    if (reportText.isEmpty) {
      ToastService.showError(
        message: i18n.translate('report_empty_error'),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUser = AppState.currentUser.value;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Buscar dados do evento para obter o activityText
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      String? activityText;
      if (eventDoc.exists) {
        final eventData = eventDoc.data();
        activityText = eventData?['activityText'] as String?;
      }

      await FirebaseFirestore.instance.collection('reports').add({
        'eventId': widget.eventId,
        'reportedBy': currentUser.userId,
        'reportText': reportText,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'event',
        if (activityText != null) 'activityText': activityText,
      });

      // ✅ Remover conversa do evento da lista de chats do usuário
      // Mesma lógica usada no leaveEvent para limpar a UI
      try {
        await FirebaseFirestore.instance
            .collection('Connections')
            .doc(currentUser.userId)
            .collection('Conversations')
            .doc('event_${widget.eventId}')
            .delete();
        debugPrint('✅ [Report] Conversa do evento removida da lista de chats');
      } catch (e) {
        debugPrint('⚠️ [Report] Erro ao remover conversa (não bloqueante): $e');
      }

      if (!context.mounted) return;

      Navigator.of(context).pop();
      
      ToastService.showSuccess(
        message: i18n.translate('report_submitted_success'),
      );
    } catch (e) {
      debugPrint('❌ Erro ao enviar denúncia: $e');
      
      if (!context.mounted) return;
      
      ToastService.showError(
        message: i18n.translate('report_submit_error'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com título e botão fechar
          Row(
            children: [
              Expanded(
                child: Text(
                  i18n.translate('report_event'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
              ),
              GlimpseCloseButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Campo de texto para denúncia
          GlimpseTextField(
            controller: _reportController,
            focusNode: _focusNode,
            hintText: i18n.translate('report_reason_hint'),
            maxLines: 6,
            maxLength: 500,
            enabled: !_isSubmitting,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),

          // Botão Enviar
          GlimpseButton(
            text: i18n.translate('send'),
            backgroundColor: GlimpseColors.error,
            textColor: Colors.white,
            height: 52,
            noPadding: true,
            isProcessing: _isSubmitting,
            onTap: _isSubmitting ? null : () => _submitReport(context),
          ),
        ],
      ),
    );
  }
}
