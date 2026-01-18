import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class BasicInfoEntry {
  BasicInfoEntry({
    required this.label, 
    required this.value, 
    this.display, 
    this.onTap,
  });
  
  final String label;
  final String value; // raw value (can be '—')
  final String? display; // optional display override
  final VoidCallback? onTap;
}

/// Section widget that renders "Basic Information" list (label left, value right)
class BasicInformationSection extends StatelessWidget {

  const BasicInformationSection({
    required this.entries, 
    super.key,
    this.title,
    this.spacing = 12,
  });
  
  final String? title;
  final List<BasicInfoEntry> entries;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final filtered = entries.where((e) {
      final v = e.value.trim();
      if (v.isEmpty) return false;
      if (v == '—') return false; // ignora placeholder
      return true;
    }).toList();

    if (filtered.isEmpty) return const SizedBox(); // não renderiza seção sem dados

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? i18n.translate('basic_information_title'),
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: GlimpseColors.primaryColorLight,
          ),
        ),
        SizedBox(height: spacing),
        Column(
          children: filtered.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLastItem = index == filtered.length - 1;
            
            return Padding(
              padding: EdgeInsets.only(bottom: isLastItem ? 0 : 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 104, // Fixed width for labels (increased by 24px)
                    child: Text(
                      item.label,
                      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: item.onTap,
                        child: Text(
                          item.display ?? item.value,
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: item.onTap != null
                                ? Theme.of(context).primaryColorLight
                                : GlimpseColors.primaryColorLight,
                            decoration: TextDecoration.none,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
