import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/plugins/locationpicker/entities/auto_complete_item.dart';

/// Overlay de sugestões de lugares
class LocationSuggestionsOverlay extends StatelessWidget {
  const LocationSuggestionsOverlay({
    super.key,
    required this.suggestions,
    required this.onTap,
    required this.top,
  });

  final List<AutoCompleteItem> suggestions;
  final void Function(String placeId, String placeName) onTap;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                return InkWell(
                  onTap: () {
                    if (suggestion.id != null && suggestion.text != null) {
                      onTap(suggestion.id!, suggestion.text!);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Image.asset('assets/images/pim.png', width: 20, height: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.text ?? '',
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: GlimpseColors.primaryColorLight,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay de loading durante busca
class LocationSearchLoadingOverlay extends StatelessWidget {
  const LocationSearchLoadingOverlay({
    super.key,
    required this.message,
    required this.top,
  });

  final String message;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(width: 12),
              Text(
                message,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  color: GlimpseColors.textSubTitle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
