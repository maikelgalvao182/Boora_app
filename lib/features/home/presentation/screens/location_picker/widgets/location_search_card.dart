import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';

/// Card unificado com título, subtítulo e campo de busca
class LocationSearchCard extends StatefulWidget {
  const LocationSearchCard({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBack,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  State<LocationSearchCard> createState() => _LocationSearchCardState();
}

class _LocationSearchCardState extends State<LocationSearchCard> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Título com ícone e botão voltar
            Row(
              children: [
                // Botão voltar
                GlimpseBackButton(
                  onTap: widget.onBack,
                  width: 24,
                  height: 24,
                ),
                const SizedBox(width: 12),
                
                // Título
                Expanded(
                  child: Text(
                    i18n.translate('choose_meeting_point'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GlimpseColors.primaryColorLight,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Subtítulo
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                i18n.translate('exact_location_visible'),
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.textSubTitle,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Campo de busca
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: GlimpseColors.lightTextField,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                onChanged: widget.onChanged,
                textAlignVertical: TextAlignVertical.center,
                maxLines: 1,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: GlimpseColors.primaryColorLight,
                ),
                decoration: InputDecoration(
                  hintText: i18n.translate('search_location'),
                  hintStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: GlimpseColors.textHint,
                  ),
                  suffixIcon: widget.controller.text.trim().isNotEmpty
                      ? IconButton(
                          onPressed: widget.onClose,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.close,
                            color: GlimpseColors.primary,
                            size: 20,
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minHeight: 40,
                    minWidth: 40,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  // Keep hint + input vertically centered inside a fixed 48px field.
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
