import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget de calendário horizontal com 7 dias
/// Permite selecionar um dia deslizando horizontalmente
class HorizontalWeekCalendar extends StatelessWidget {
  const HorizontalWeekCalendar({
    required this.selectedDate,
    required this.onDateSelected,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  /// Gera lista com 7 dias a partir de hoje
  List<DateTime> get _weekDays {
    final today = DateTime.now();
    return List.generate(7, (index) => today.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _weekDays.length,
        itemBuilder: (context, index) {
          final date = _weekDays[index];
          final isSelected = selectedDate.day == date.day &&
              selectedDate.month == date.month &&
              selectedDate.year == date.year;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _DayCard(
              date: date,
              isSelected: isSelected,
              onTap: () => onDateSelected(date),
              locale: AppLocalizations.of(context).locale,
            ),
          );
        },
      ),
    );
  }
}

/// Card individual de cada dia
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.isSelected,
    required this.onTap,
    required this.locale,
  });

  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    // Usar o locale correto baseado no idioma do app
    final localeString = locale.languageCode == 'pt' ? 'pt_BR' : 
                        locale.languageCode == 'es' ? 'es_ES' : 'en_US';
    
    // Formata dia da semana com primeira letra maiúscula
    final weekDay = DateFormat('EEE', localeString).format(date);
    final weekDayCapitalized = weekDay[0].toUpperCase() + weekDay.substring(1);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: isSelected
              ? GlimpseColors.primary
              : GlimpseColors.lightTextField,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Dia da semana
            Text(
              weekDayCapitalized,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : GlimpseColors.textSubTitle,
              ),
            ),

            // Data
            Text(
              DateFormat('d', localeString).format(date),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white
                    : GlimpseColors.primaryColorLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
