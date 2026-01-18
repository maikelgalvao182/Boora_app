import 'package:flutter/material.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/report_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';

/// 🚩 Diálogo profissional de denúncia
/// 
/// Permite ao usuário enviar uma mensagem explicando o motivo da denúncia
class ReportDetailsDialog extends StatefulWidget {
  const ReportDetailsDialog({
    super.key,
    required this.userId,
    this.eventId,
  });

  final String userId;
  final String? eventId;

  static Future<bool?> show(
    BuildContext context, {
    required String userId,
    String? eventId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReportDetailsDialog(
        userId: userId,
        eventId: eventId,
      ),
    );
  }

  @override
  State<ReportDetailsDialog> createState() => _ReportDetailsDialogState();
}

class _ReportDetailsDialogState extends State<ReportDetailsDialog> {
  AppLocalizations? _i18n;
  final _messageController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_i18n == null) {
      _i18n = AppLocalizations.of(context);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _close([bool? result]) {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _submitReport() async {
    final message = _messageController.text.trim();

    if (message.isEmpty) {
      setState(() => _errorMessage = _i18n!.translate('report_message_empty'));
      return;
    }

    if (message.length < 10) {
      setState(() => _errorMessage = _i18n!.translate('report_message_too_short'));
      return;
    }

    // Limpa erro se validação passou
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    setState(() => _isLoading = true);

    try {
      await ReportService.instance.sendReport(
        message: message,
        targetUserId: widget.userId,
        eventId: widget.eventId,
      );

      if (mounted) {
        _showSuccess(_i18n!.translate('report_sent_successfully'));
        _close(true);
      }
    } catch (e) {
      if (mounted) {
        _showError(_i18n!.translate('report_error'));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ToastService.showError(message: message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ToastService.showSuccess(message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildTextField(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                _buildErrorText(),
              ],
              const SizedBox(height: 20),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: Text(
            _i18n!.translate('report_details_title'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: GlimpseCloseButton(onPressed: () => _close()),
        ),
      ],
    );
  }

  Widget _buildDescription() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        _i18n!.translate('report_details_description'),
        textAlign: TextAlign.center,
        style: DialogStyles.messageStyle.copyWith(fontSize: 13),
      ),
    );
  }

  Widget _buildTextField() {
    return GlimpseTextField(
      controller: _messageController,
      focusNode: _focusNode,
      hintText: _i18n!.translate('report_details_placeholder'),
      maxLines: 5,
      maxLength: 500,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildErrorText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        _errorMessage!,
        style: const TextStyle(
          color: Colors.red,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => _close(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.grey[400]!),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _i18n!.translate('cancel'),
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _i18n!.translate('send_report'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
