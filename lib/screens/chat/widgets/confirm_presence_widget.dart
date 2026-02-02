import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/widgets/presence_drawer.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';

/// Widget para confirmar presença em eventos
/// 
/// Exibe botão compacto que expande para mostrar opções:
/// - Eu vou
/// - Talvez
/// - Não vou
/// - Ver lista
class ConfirmPresenceWidget extends StatefulWidget {
  const ConfirmPresenceWidget({
    required this.applicationId,
    required this.eventId,
    super.key,
  });

  final String applicationId;
  final String eventId;

  @override
  State<ConfirmPresenceWidget> createState() => _ConfirmPresenceWidgetState();
}

class _ConfirmPresenceWidgetState extends State<ConfirmPresenceWidget> {
  bool _isExpanded = false;
  bool _isUpdating = false;
  String _currentPresence = 'Talvez'; // Estado padrão

  @override
  void initState() {
    super.initState();
    _loadCurrentPresence();
  }

  Future<void> _loadCurrentPresence() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('EventApplications')
          .doc(widget.applicationId)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _currentPresence = doc.data()?['presence'] ?? 'Talvez';
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar presença: $e');
    }
  }

  Future<void> _updatePresence(String presenceValue) async {
    if (_isUpdating) return;

    if (!mounted) return;
    setState(() => _isUpdating = true);

    try {
      await FirebaseFirestore.instance
          .collection('EventApplications')
          .doc(widget.applicationId)
          .update({'presence': presenceValue});

      debugPrint('✅ Presença atualizada: $presenceValue');

      // Atualiza estado local
      if (mounted) {
        setState(() {
          _currentPresence = presenceValue;
          _isExpanded = false;
          _isUpdating = false;
        });
      }

      // Feedback visual
      if (mounted) {
        final i18n = AppLocalizations.of(context);
        ToastService.showSuccess(
          message: i18n.translate('presence_updated'),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao atualizar presença: $e');
      
      if (mounted) {
        setState(() => _isUpdating = false);
      }

      if (mounted) {
        final i18n = AppLocalizations.of(context);
        ToastService.showError(
          message: i18n.translate('presence_update_error'),
        );
      }
    }
  }

  void _openPresenceDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PresenceDrawer(eventId: widget.eventId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return RepaintBoundary(
      child: Container(
        decoration: const BoxDecoration(
          color: GlimpseColors.primaryLight,
          border: Border(
            bottom: BorderSide(
              color: GlimpseColors.primaryLight,
              width: 1,
            ),
          ),
        ),
        child: Column(
          children: [
            // Botão principal - Listener captura toque ANTES do Material
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _isUpdating ? null : (_) {
                setState(() => _isExpanded = !_isExpanded);
              },
              child: Container(
                color: GlimpseColors.primaryLight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Text(
                      '🙋',
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      i18n.translate('confirm_presence'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: GlimpseColors.primaryColorLight,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

          // Opções expandidas
          RepaintBoundary(
            child: AnimatedExpandable(
              isExpanded: _isExpanded,
              child: Container(
                color: GlimpseColors.primaryLight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _PresenceButton(
                        emoji: '✅',
                        label: i18n.translate('presence_yes'),
                        isSelected: _currentPresence == 'Vou',
                        onTap: _isUpdating ? null : () => _updatePresence('Vou'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PresenceButton(
                        emoji: '🤔',
                        label: i18n.translate('presence_maybe'),
                        isSelected: _currentPresence == 'Talvez',
                        onTap: _isUpdating ? null : () => _updatePresence('Talvez'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PresenceButton(
                        emoji: '❌',
                        label: i18n.translate('presence_no'),
                        isSelected: _currentPresence == 'Não vou',
                        onTap: _isUpdating ? null : () => _updatePresence('Não vou'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PresenceButton(
                        emoji: '👁️',
                        label: i18n.translate('presence_view_list'),
                        isSelected: false,
                        onTap: _isUpdating ? null : _openPresenceDrawer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// Botão de presença const reutilizável
class _PresenceButton extends StatelessWidget {
  const _PresenceButton({
    required this.emoji,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onTap != null ? (_) => onTap!() : null,
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? GlimpseColors.primaryLight
              : GlimpseColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(
                  color: GlimpseColors.primary,
                  width: 2,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}