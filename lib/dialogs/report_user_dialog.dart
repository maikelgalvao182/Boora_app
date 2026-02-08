import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/dialogs/report_details_dialog.dart';

class ReportDialog extends StatefulWidget {
  const ReportDialog({
    super.key,
    required this.userId,
    this.isStoryProfile = false,
    this.avatarUrl,
    this.onBlockSuccess,
  });

  final String userId;
  final bool isStoryProfile;
  final String? avatarUrl;
  final VoidCallback? onBlockSuccess;

  void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => this,
    );
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  AppLocalizations? _i18n;
  String? _blockText;
  String? _reportText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_i18n == null) {
      _i18n = AppLocalizations.of(context);
      _blockText = _i18n!.translate('Block');
      _reportText = _i18n!.translate('report');
    }
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _reportProfile() {
    _close();
    
    // Abre o diálogo de denúncia com campo de texto
    ReportDetailsDialog.show(
      context,
      userId: widget.userId,
    );
  }

  Future<void> _confirmBlock() async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) {
      debugPrint('❌ [ReportDialog] Usuário não autenticado');
      return;
    }

    _close();
    
    try {
      await BlockService().blockUser(currentUserId, widget.userId);
      debugPrint('✅ [ReportDialog] Usuário bloqueado: ${widget.userId}');
      
      // Executa callback de sucesso (ex: navegação)
      widget.onBlockSuccess?.call();
      
      // Fecha a tela de perfil se estiver aberta
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ [ReportDialog] Erro ao bloquear: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      top: false,
      child: _ReportDialogContent(),
    );
  }
}

/// Widget interno extraído para evitar rebuilds desnecessários
class _ReportDialogContent extends StatelessWidget {
  const _ReportDialogContent();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_ReportDialogState>()!;
    
    return Container(
      margin: EdgeInsets.all(16.w),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            title: state._i18n!.translate('create_report'),
            onClose: state._close,
          ),
          SizedBox(height: 16.h),
          _Avatar(userId: state.widget.userId),
          SizedBox(height: 24.h),
          _Title(text: state._i18n!.translate('help_us_keep_community_safe')),
          SizedBox(height: 12.h),
          _Description(text: state._i18n!.translate('report_dialog_description')),
          SizedBox(height: 20.h),
          _ActionButtons(
            blockText: state._blockText!,
            reportText: state._reportText!,
            onBlock: state._confirmBlock,
            onReport: state._reportProfile,
          ),
        ],
      ),
    );
  }
}

/// Header com título centralizado e botão de fechar
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onClose,
  });
  
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: GlimpseCloseButton(onPressed: onClose),
        ),
      ],
    );
  }
}

/// Botão de fechar isolado
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});
  
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GlimpseCloseButton(onPressed: onPressed),
      ],
    );
  }
}

/// Avatar isolado (não rebuilda)
class _Avatar extends StatelessWidget {
  const _Avatar({required this.userId});
  
  final String userId;

  @override
  Widget build(BuildContext context) {
    return StableAvatar(
      userId: userId,
      size: 90,
      enableNavigation: false,
    );
  }
}

/// Título isolado
class _Title extends StatelessWidget {
  const _Title({required this.text});
  
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: DialogStyles.titleStyle,
    );
  }
}

/// Descrição isolada
class _Description extends StatelessWidget {
  const _Description({required this.text});
  
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: DialogStyles.messageStyle,
      ),
    );
  }
}

/// Botões de ação isolados
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.blockText,
    required this.reportText,
    required this.onBlock,
    required this.onReport,
  });

  final String blockText;
  final String reportText;
  final VoidCallback onBlock;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DialogStyles.buildNegativeButton(
          text: blockText,
          onPressed: onBlock,
        ),
        const SizedBox(width: DialogStyles.buttonSpacing),
        Expanded(
          child: ElevatedButton(
            onPressed: onReport,
            style: DialogStyles.positiveButtonStyle,
            child: Text(
              reportText,
              style: DialogStyles.positiveButtonTextStyle,
            ),
          ),
        ),
      ],
    );
  }
}
