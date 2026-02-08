import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/report_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';

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
                      borderRadius: BorderRadius.circular(20.r),
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
          borderRadius: BorderRadius.circular(8.r),
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

/// Enum para os motivos de denúncia
enum ReportReason {
  violenceDrugs,
  pornographyNudity,
  underage,
  fakeProfile,
  other,
}

class _ReportDialogContentState extends State<_ReportDialogContent> {
  final TextEditingController _reportController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;
  ReportReason? _selectedReason;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _reportController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _getReasonText(ReportReason reason, AppLocalizations i18n) {
    switch (reason) {
      case ReportReason.violenceDrugs:
        return i18n.translate('report_reason_violence_drugs');
      case ReportReason.pornographyNudity:
        return i18n.translate('report_reason_pornography');
      case ReportReason.underage:
        return i18n.translate('report_reason_underage');
      case ReportReason.fakeProfile:
        return i18n.translate('report_reason_fake_profile');
      case ReportReason.other:
        return i18n.translate('report_reason_other');
    }
  }

  Future<void> _submitReport(BuildContext context) async {
    final i18n = AppLocalizations.of(context);
    final otherText = _reportController.text.trim();

    if (_selectedReason == null) {
      ToastService.showError(
        message: i18n.translate('report_select_reason_error'),
      );
      return;
    }

    if (_selectedReason == ReportReason.other && otherText.isEmpty) {
      ToastService.showError(
        message: i18n.translate('report_empty_error'),
      );
      _focusNode.requestFocus();
      return;
    }

    final reportText = _selectedReason == ReportReason.other
        ? '${_getReasonText(_selectedReason!, i18n)}: $otherText'
        : _getReasonText(_selectedReason!, i18n);

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUser = AppState.currentUser.value;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Buscar dados do evento para obter o activityText e ownerId
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      String? activityText;
      String? eventOwnerId;
      if (eventDoc.exists) {
        final eventData = eventDoc.data();
        activityText = eventData?['activityText'] as String?;
        eventOwnerId = eventData?['ownerId'] as String?;
      }

      await FirebaseFirestore.instance.collection('reports').add({
        'eventId': widget.eventId,
        'reportedBy': currentUser.userId,
        'reportText': reportText,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'event',
        if (activityText != null) 'activityText': activityText,
        if (eventOwnerId != null) 'eventOwnerId': eventOwnerId,
      });

      // ✅ Criar report do dono do evento também (mesma lógica do ReportWidget no perfil)
      if (eventOwnerId != null && eventOwnerId != currentUser.userId) {
        try {
          await ReportService.instance.sendReport(
            message: reportText,
            targetUserId: eventOwnerId,
            eventId: widget.eventId,
          );
          debugPrint('✅ [Report] Report do dono do evento criado: $eventOwnerId');
        } catch (e) {
          debugPrint('⚠️ [Report] Erro ao criar report do dono (não bloqueante): $e');
        }
      }

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

  Widget _buildRadioOption(ReportReason reason, AppLocalizations i18n) {
    final isSelected = _selectedReason == reason;
    return InkWell(
      onTap: _isSubmitting
          ? null
          : () {
              setState(() {
                _selectedReason = reason;
              });
              if (reason == ReportReason.other) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _focusNode.requestFocus();
                });
              }
            },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? GlimpseColors.error : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: GlimpseColors.error,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _getReasonText(reason, i18n),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 15.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? GlimpseColors.primaryColorLight
                      : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final isOtherSelected = _selectedReason == ReportReason.other;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com título e botão fechar/voltar
          Row(
            children: [
              Expanded(
                child: Text(
                  i18n.translate('report_event'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
              ),
              // Botão voltar substitui o fechar quando "Outro" está selecionado
              if (isOtherSelected)
                GlimpseBackButton(
                  onTap: () {
                    setState(() {
                      _selectedReason = null;
                      _reportController.clear();
                    });
                    _focusNode.unfocus();
                  },
                )
              else
                GlimpseCloseButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Radio options (esconde quando "Outro" está selecionado)
          AnimatedExpandable(
            isExpanded: !isOtherSelected,
            duration: const Duration(milliseconds: 250),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRadioOption(ReportReason.violenceDrugs, i18n),
                _buildRadioOption(ReportReason.pornographyNudity, i18n),
                _buildRadioOption(ReportReason.underage, i18n),
                _buildRadioOption(ReportReason.fakeProfile, i18n),
                _buildRadioOption(ReportReason.other, i18n),
              ],
            ),
          ),

          // Campo de texto expandível para "Outro"
          AnimatedExpandable(
            isExpanded: isOtherSelected,
            duration: const Duration(milliseconds: 250),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.translate('report_reason_hint'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: _focusNode,
                    builder: (context, _) {
                      final hasFocus = _focusNode.hasFocus;
                      return TextField(
                        controller: _reportController,
                        focusNode: _focusNode,
                        maxLines: 4,
                        maxLength: 300,
                        enabled: !_isSubmitting,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          color: GlimpseColors.primaryColorLight,
                        ),
                        decoration: InputDecoration(
                          hintText: i18n.translate('report_details_placeholder'),
                          hintStyle: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14,
                            color: Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: hasFocus ? Colors.white : Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: GlimpseColors.error,
                              width: 1.5,
                            ),
                          ),
                          counterText: '',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

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
