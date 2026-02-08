import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/animated_removal_wrapper.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Card genérico para ações pendentes (aprovações, reviews, etc)
/// 
/// Exibe:
/// - Avatar do usuário
/// - Texto formatado com nome em negrito
/// - Tempo relativo
/// - Dois botões de ação customizáveis
class ActionCard extends StatefulWidget {
  const ActionCard({
    required this.userId,
    required this.userPhotoUrl,
    required this.textSpans,
    required this.timeAgo,
    required this.primaryButtonText,
    required this.primaryButtonColor,
    required this.onPrimaryAction,
    required this.secondaryButtonText,
    required this.secondaryButtonColor,
    required this.onSecondaryAction,
    super.key,
  });

  final String userId;
  final String? userPhotoUrl;
  final List<TextSpan> textSpans;
  final String timeAgo;
  final String primaryButtonText;
  final Color primaryButtonColor;
  final Future<void> Function() onPrimaryAction;
  final String secondaryButtonText;
  final Color secondaryButtonColor;
  final Future<void> Function() onSecondaryAction;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  final GlobalKey<AnimatedRemovalWrapperState> _animationKey = GlobalKey();
  bool _isProcessing = false;

  /// Converte fullName em displayName (primeiro nome + inicial do último)
  String _buildDisplayName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Usuário';

    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Usuário';

    final first = parts.first;
    if (parts.length == 1) {
      return first.length > 15 ? first.substring(0, 15) : first;
    }

    final lastInitial = parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
    final safeFirst = first.length > 15 ? first.substring(0, 15) : first;
    return lastInitial.isEmpty ? safeFirst : '$safeFirst $lastInitial.';
  }

  Future<void> _handlePrimaryAction() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      await widget.onPrimaryAction();
      if (mounted) {
        await _animationKey.currentState?.animateRemoval();
      }
    } catch (e) {
      debugPrint('❌ Erro na ação primária: $e');
      if (mounted) {
        final i18n = AppLocalizations.of(context);
        ToastService.showError(message: i18n.translate('action_error'));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleSecondaryAction() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      await widget.onSecondaryAction();
      if (mounted) {
        await _animationKey.currentState?.animateRemoval();
      }
    } catch (e) {
      debugPrint('❌ Erro na ação secundária: $e');
      if (mounted) {
        final i18n = AppLocalizations.of(context);
        ToastService.showError(message: i18n.translate('action_error'));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedRemovalWrapper(
      key: _animationKey,
      onRemove: () {
        // Callback vazio - a remoção real acontece via Stream
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Builder(
              builder: (context) {
                debugPrint('📸 ActionCard StableAvatar - userId: ${widget.userId}');
                debugPrint('📸 ActionCard StableAvatar - photoUrl: ${widget.userPhotoUrl}');
                debugPrint('📸 ActionCard StableAvatar - photoUrl is null? ${widget.userPhotoUrl == null}');
                debugPrint('📸 ActionCard StableAvatar - photoUrl is empty? ${widget.userPhotoUrl?.isEmpty ?? true}');
                
                return StableAvatar(
                  userId: widget.userId,
                  photoUrl: widget.userPhotoUrl,
                  size: 48,
                  borderRadius: BorderRadius.circular(8),
                  enableNavigation: true,
                );
              },
            ),

            const SizedBox(width: 12),

            // Informações e Botões
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Texto formatado com nome reativo do UserStore
                  ValueListenableBuilder<String?>(
                    valueListenable: UserStore.instance.getNameNotifier(widget.userId),
                    builder: (context, reactiveName, _) {
                      // Substituir o primeiro TextSpan (nome) pelo nome reativo
                      final displayName = _buildDisplayName(reactiveName ?? '');
                      
                      // Criar novos textSpans com o nome reativo
                      final updatedSpans = <TextSpan>[
                        TextSpan(
                          text: displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        // Adicionar os demais spans (exceto o primeiro que era o nome)
                        if (widget.textSpans.length > 1)
                          ...widget.textSpans.skip(1),
                      ];

                      return RichText(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.primaryColorLight,
                          ),
                          children: updatedSpans,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 4),

                  // Tempo relativo
                  Text(
                    widget.timeAgo,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botões de ação
                  Row(
                    children: [
                      Expanded(
                        child: GlimpseButton(
                          text: widget.primaryButtonText,
                          backgroundColor: widget.primaryButtonColor,
                          height: 38,
                          fontSize: 14,
                          noPadding: true,
                          isProcessing: _isProcessing,
                          hideProcessingText: true,
                          onPressed: _handlePrimaryAction,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GlimpseButton(
                          text: widget.secondaryButtonText,
                          backgroundColor: widget.secondaryButtonColor,
                          height: 38,
                          fontSize: 14,
                          noPadding: true,
                          isProcessing: _isProcessing,
                          hideProcessingText: true,
                          onPressed: _handleSecondaryAction,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
