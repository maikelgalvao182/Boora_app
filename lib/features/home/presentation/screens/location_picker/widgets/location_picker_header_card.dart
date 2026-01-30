import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_segmented_tabs.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';

/// Card unificado que contém tabs + título/subtítulo dinâmico + campo de busca expansível
class LocationPickerHeaderCard extends StatefulWidget {
  const LocationPickerHeaderCard({
    super.key,
    required this.selectedTabIndex,
    required this.onTabChanged,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchClose,
  });

  final int selectedTabIndex;
  final ValueChanged<int> onTabChanged;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClose;

  @override
  State<LocationPickerHeaderCard> createState() => _LocationPickerHeaderCardState();
}

class _LocationPickerHeaderCardState extends State<LocationPickerHeaderCard> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onTextChanged);
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
    
    // Textos dinâmicos baseados na tab selecionada
    final title = widget.selectedTabIndex == 0
        ? i18n.translate('location_picker_map_hint')
        : i18n.translate('choose_meeting_point');
    
    final subtitle = widget.selectedTabIndex == 0
        ? i18n.translate('tap_map_to_confirm')
        : i18n.translate('exact_location_visible');

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
            // Tabs
            Container(
              height: 48,
              child: GlimpseSegmentedTabs(
                labels: [
                  i18n.translate('location_picker_tab_map'),
                  i18n.translate('location_picker_tab_search'),
                ],
                currentIndex: widget.selectedTabIndex,
                backgroundColor: GlimpseColors.lightTextField,
                selectedTabColor: GlimpseColors.primary,
                selectedTextColor: Colors.white,
                unselectedTextColor: GlimpseColors.textSubTitle,
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(4),
                onChanged: widget.onTabChanged,
              ),
            ),

            const SizedBox(height: 16),

            // Título (sempre visível)
            Text(
              title,
              textAlign: TextAlign.left,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: GlimpseColors.primaryColorLight,
              ),
            ),

            const SizedBox(height: 8),

            // Subtítulo (sempre visível)
            Text(
              subtitle,
              textAlign: TextAlign.left,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: GlimpseColors.textSubTitle,
              ),
            ),

            // Campo de busca expansível (apenas quando tab == 1)
            AnimatedExpandable(
              isExpanded: widget.selectedTabIndex == 1,
              clip: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: GlimpseColors.lightTextField,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: widget.searchController,
                      focusNode: widget.searchFocusNode,
                      onChanged: widget.onSearchChanged,
                      textAlignVertical: TextAlignVertical.center,
                      maxLines: 1,
                      scrollPadding: EdgeInsets.zero,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.primaryColorLight,
                      ),
                      decoration: InputDecoration(
                        hintText: i18n.translate('search_location'),
                        hintStyle: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textHint,
                        ),
                        suffixIcon: widget.searchController.text.trim().isNotEmpty
                            ? IconButton(
                                onPressed: widget.onSearchClose,
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
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
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
