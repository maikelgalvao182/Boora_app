import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget compacto de calendário horizontal para filtro de data no mapa
/// Mostra apenas 2-3 dias visíveis com fade nas bordas para indicar scroll
class DateFilterCalendar extends StatefulWidget {
  const DateFilterCalendar({
    required this.selectedDate,
    required this.onDateSelected,
    this.showShadow = true,
    this.unselectedColor = Colors.white,
    this.expandWidth = false,
    this.availableWidth,
    super.key,
  });

  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onDateSelected;
  final bool showShadow;
  final Color unselectedColor;
  final bool expandWidth;
  final double? availableWidth;

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
      // Cada card tem 56 de largura + espaçamento horizontal responsivo
      final isLargeScreen = MediaQuery.sizeOf(context).width > 390;
      final cardSize = isLargeScreen ? math.min(56.0, 56.w) : 56.w;
      final cardSpacing = isLargeScreen ? math.min(8.0, 8.w) : math.min(4.0, 4.w);
      final itemExtent = cardSize + cardSpacing;
      final targetOffset = (selectedIndex * itemExtent).clamp(
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
    // Responsivo: usa largura disponível no contexto do overlay (não largura do device)
    final availableWidth = widget.availableWidth ?? MediaQuery.of(context).size.width;
    final isLargeScreen = MediaQuery.sizeOf(context).width > 390;
    final cardSize = isLargeScreen ? math.min(56.0, 56.w) : 56.w;
    final cardSpacing = isLargeScreen ? math.min(8.0, 8.w) : math.min(4.0, 4.w);
    final calendarHeight = isLargeScreen ? math.min(56.0, 56.h) : 56.h;
    final verticalInset = math.min(8.0, 8.h);
    final outerHorizontalPadding = math.min(16.0, 16.w);
    final compactThreshold = 230.w;
    final visibleDays = availableWidth <= compactThreshold ? 2 : 3;
    final isCompactScreen = visibleDays == 2;

    final compactWidth = cardSize * 2;
    final regularWidth = cardSize * 3;
    final calendarWidth = widget.expandWidth
        ? double.infinity
      : (visibleDays == 2 ? compactWidth : regularWidth).clamp(96.w, availableWidth);
    
    return SizedBox(
      height: calendarHeight, // Altura visual do calendário
      width: calendarWidth,
      child: Stack(
        clipBehavior: Clip.none, // Permite overflow vertical para sombra
        children: [
          Positioned.fill(
            top: -verticalInset,
            bottom: -verticalInset,
            child: ClipRRect(
              borderRadius: widget.expandWidth ? BorderRadius.zero : BorderRadius.circular(100.r),
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: widget.expandWidth 
                    ? EdgeInsets.fromLTRB(outerHorizontalPadding, verticalInset, outerHorizontalPadding, verticalInset)
                  : EdgeInsets.fromLTRB(0, verticalInset, 0, verticalInset),
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
                    padding: EdgeInsets.only(right: isLast ? 0 : cardSpacing),
                    child: _CompactDayCard(
                      date: date,
                      isSelected: isSelected,
                      showShadow: widget.showShadow,
                      unselectedColor: widget.unselectedColor,
                      cardSize: cardSize,
                      onTap: () {
                        // Toggle: se já está selecionado, deseleciona (mostra todos)
                        if (isSelected) {
                          widget.onDateSelected(null);
                        } else {
                          widget.onDateSelected(date);
                        }
                      },
                      locale: AppLocalizations.of(context).locale,
                      isCompactScreen: isCompactScreen,
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
    required this.isCompactScreen,
    required this.cardSize,
    this.showShadow = true,
    this.unselectedColor = Colors.white,
  });

  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;
  final Locale locale;
  final bool isCompactScreen;
  final double cardSize;
  final bool showShadow;
  final Color unselectedColor;

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
        width: cardSize,
        height: cardSize,
        decoration: BoxDecoration(
          color: isSelected
              ? GlimpseColors.primary
              : unselectedColor,
          shape: BoxShape.circle,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8.r,
                    offset: Offset(0, 4.h),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Dia da semana (3 letras)
            Text(
              weekDayCapitalized,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: (isCompactScreen ? 8 : 9).sp,
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
                fontSize: (isCompactScreen ? 13 : 14).sp,
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
