import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget compartilhado para exibir barras de critérios de avaliação
class CriteriaBars extends StatelessWidget {
  const CriteriaBars({
    required this.criteriaRatings,
    super.key,
    this.showDivider = true,
    this.showEmojis = false,
    this.barColor,
    this.showDecimals = false,
  });

  final Map<String, double> criteriaRatings;
  final bool showDivider;
  final bool showEmojis;
  final Color? barColor;
  final bool showDecimals;

  Map<String, String> _criteriaLabels(BuildContext context) => {
    'conversation': AppLocalizations.of(context).translate('review_criteria_conversation_short'),
    'energy': AppLocalizations.of(context).translate('review_criteria_energy_short'),
    'participation': AppLocalizations.of(context).translate('review_criteria_participation'),
    'coexistence': AppLocalizations.of(context).translate('review_criteria_coexistence'),
  };

  Map<String, String> _criteriaLabelsDetailed(BuildContext context) => {
    'conversation': AppLocalizations.of(context).translate('review_criteria_conversation'),
    'energy': AppLocalizations.of(context).translate('review_criteria_energy_short'),
    'participation': AppLocalizations.of(context).translate('review_criteria_participation'),
    'coexistence': AppLocalizations.of(context).translate('review_criteria_coexistence'),
  };

  static const Map<String, String> _criteriaEmojis = {
    'conversation': '💬',
    'energy': '⚡',
    'participation': '🎯',
    'coexistence': '🤝',
  };

  static const List<String> _mainCriteria = [
    'conversation',
    'energy',
    'participation',
    'coexistence',
  ];

  @override
  Widget build(BuildContext context) {
    // Filtrar apenas os critérios que temos dados
    final displayCriteria = _mainCriteria
        .where((key) => criteriaRatings.containsKey(key))
        .toList();
    
    if (displayCriteria.isEmpty) return const SizedBox.shrink();
    
    final criteriaLabels = _criteriaLabels(context);
    final criteriaLabelsDetailed = _criteriaLabelsDetailed(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider opcional
        if (showDivider)
          Container(
            height: 1,
            color: GlimpseColors.borderColorLight,
            margin: EdgeInsets.only(bottom: 8.h),
          ),
        
        // Barras de critério
        ...displayCriteria.asMap().entries.map((entry) {
          final index = entry.key;
          final key = entry.value;
          final isLast = index == displayCriteria.length - 1;
          final rating = criteriaRatings[key] ?? 0.0;
          final label = showEmojis ? criteriaLabelsDetailed[key] : criteriaLabels[key];
          final emoji = _criteriaEmojis[key];
          
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : (showEmojis ? 12 : 6)),
            child: showEmojis
                ? _buildDetailedBar(key, rating, label ?? key, emoji ?? '⭐')
                : _buildSimpleBar(context, key, rating, label ?? key),
          );
        }),
      ],
    );
  }

  Widget _buildSimpleBar(BuildContext context, String key, double rating, String label) {
    final i18n = AppLocalizations.of(context);
    final template = i18n.translate('criteria_label_with_colon');
    final labelText = template.isNotEmpty
        ? template.replaceAll('{label}', label)
        : '$label:';

    return Row(
      children: [
        // Label
        SizedBox(
          width: 90,
          child: Text(
            labelText,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ),
        
        // Barra de progresso
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rating / 5.0,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                barColor ?? _getColorForRating(rating),
              ),
              minHeight: 6,
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Valor numérico
        SizedBox(
          width: 20,
          child: Text(
            showDecimals ? rating.toStringAsFixed(1) : rating.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedBar(String key, double rating, String label, String emoji) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: TextStyle(fontSize: 16.sp)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.textSecondary,
                ),
              ),
            ),
            Text(
              rating.toStringAsFixed(1),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: barColor ?? GlimpseColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: rating / 5,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(barColor ?? GlimpseColors.primary),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Color _getColorForRating(double rating) {
    if (rating >= 4.5) {
      return Colors.green;
    } else if (rating >= 3.5) {
      return GlimpseColors.primaryColorLight;
    } else if (rating >= 2.5) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}
