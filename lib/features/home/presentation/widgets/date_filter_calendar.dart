import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget compacto de calendário horizontal para filtro de data no mapa
/// Mostra apenas 2-3 dias visíveis com fade nas bordas para indicar scroll
class DateFilterCalendar extends StatefulWidget {
  const DateFilterCalendar({
    required this.selectedDate,
    required this.onDateSelected,
    super.key,
  });

  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onDateSelected;

  @override
  State<DateFilterCalendar> createState() => _DateFilterCalendarState();
}

class _DateFilterCalendarState extends State<DateFilterCalendar> {
  late final ScrollController _scrollController;
  
  /// Gera lista com 7 dias a partir de hoje
  List<DateTime> get _weekDays {
    final today = DateTime.now();
    return List.generate(7, (index) => today.add(Duration(days: index)));
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    // Scroll para o dia selecionado após build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
    });
  }
  
  @override
  void didUpdateWidget(covariant DateFilterCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _scrollToSelected();
    }
  }
  
  void _scrollToSelected() {
    if (widget.selectedDate == null) return;
    
    final selectedIndex = _weekDays.indexWhere((date) =>
        date.day == widget.selectedDate!.day &&
        date.month == widget.selectedDate!.month &&
        date.year == widget.selectedDate!.year);
    
    if (selectedIndex >= 0 && _scrollController.hasClients) {
      // Cada card tem 56 de largura + 8 de padding
      final targetOffset = (selectedIndex * 64.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsivo: telas pequenas mostram 2 círculos, telas maiores mostram 3
    final screenWidth = MediaQuery.of(context).size.width;
    final calendarWidth = screenWidth < 380 ? 128.0 : 192.0; // 2 círculos vs 3 círculos
    
    return SizedBox(
      height: 56, // Altura visual do calendário
      width: calendarWidth,
      child: Stack(
        clipBehavior: Clip.none, // Permite overflow vertical para sombra
        children: [
          Positioned.fill(
            top: -8,
            bottom: -8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8), // Padding para sombra
                physics: const BouncingScrollPhysics(),
                itemCount: _weekDays.length,
                itemBuilder: (context, index) {
                  final date = _weekDays[index];
                  final isSelected = widget.selectedDate != null &&
                      widget.selectedDate!.day == date.day &&
                      widget.selectedDate!.month == date.month &&
                      widget.selectedDate!.year == date.year;
                  final isLast = index == _weekDays.length - 1;

                  return Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 8),
                    child: _CompactDayCard(
                      date: date,
                      isSelected: isSelected,
                      onTap: () {
                        // Toggle: se já está selecionado, deseleciona (mostra todos)
                        if (isSelected) {
                          widget.onDateSelected(null);
                        } else {
                          widget.onDateSelected(date);
                        }
                      },
                      locale: AppLocalizations.of(context).locale,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card compacto individual de cada dia
class _CompactDayCard extends StatelessWidget {
  const _CompactDayCard({
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
    
    // Formata dia da semana com 3 letras
    final weekDay = DateFormat('EEE', localeString).format(date);
    final weekDayCapitalized = weekDay[0].toUpperCase() + weekDay.substring(1, 3);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected
              ? GlimpseColors.primary
              : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Dia da semana (3 letras)
            Text(
              weekDayCapitalized,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : GlimpseColors.textSubTitle,
              ),
            ),

            // Data (número)
            Text(
              DateFormat('d', localeString).format(date),
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
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
