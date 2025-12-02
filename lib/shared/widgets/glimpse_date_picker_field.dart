import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/date_formatter_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';

/// Campo de seleção de data estilo Glimpse com internacionalização
/// 
/// Formata automaticamente conforme o locale:
/// - en: MM-DD-YYYY
/// - pt: DD-MM-YYYY
/// - es: DD-MM-YYYY
class GlimpseDatePickerField extends StatefulWidget {

  const GlimpseDatePickerField({
    required this.onDateChanged, super.key,
    this.hintText,
    this.initialDate,
    this.minYear = 1920,
    this.maxYear = 2023,
  });
  final String? hintText;
  final Function(DateTime) onDateChanged;
  final DateTime? initialDate;
  final int minYear;
  final int maxYear;

  @override
  State<GlimpseDatePickerField> createState() => _GlimpseDatePickerFieldState();
}

class _GlimpseDatePickerFieldState extends State<GlimpseDatePickerField> {
  final TextEditingController _controller = TextEditingController();
  late DateTime _selectedDate;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Formata a data inicial apenas uma vez quando as dependências estiverem prontas
    if (!_isInitialized && widget.initialDate != null) {
      _updateTextFieldValue(_selectedDate);
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateTextFieldValue(DateTime date) {
    // Usa DateFormatterHelper para formatar conforme o locale
    // en: MM-DD-YYYY, pt/es: DD-MM-YYYY
    final locale = Localizations.localeOf(context).languageCode;
    final formattedDate = DateFormatterHelper.formatBirthday(date, locale);
    _controller.text = formattedDate;
  }

  /// Retorna o hintText localizado baseado no locale atual
  String _getLocalizedHintText() {
    final i18n = AppLocalizations.of(context);
    final locale = i18n.locale.languageCode;
    
    // en: MM-DD-YYYY, pt/es: DD-MM-YYYY
    if (locale == 'en') {
      return 'MM-DD-YYYY';
    } else {
      return 'DD-MM-YYYY';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: SizedBox(
        height: 60,
        width: double.infinity,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.none, // Desativa o teclado
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            color: GlimpseColors.textSubTitle,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            showModalBottomSheet(
              backgroundColor: Colors.white,
              shape: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(15),
                  topLeft: Radius.circular(15),
                ),
                borderSide: BorderSide.none,
              ),
              context: context,
              builder: (BuildContext context) {
                return Container(
                  height: 220,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(15),
                      topRight: Radius.circular(15),
                    ),
                  ),
                  padding: const EdgeInsets.all(0),
                  margin: const EdgeInsets.all(0),
                  width: double.maxFinite,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        pickerTextStyle: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      backgroundColor: Colors.white,
                      mode: CupertinoDatePickerMode.date,
                      itemExtent: 35,
                      // American order: Month - Day - Year
                      dateOrder: DatePickerDateOrder.mdy,
                      initialDateTime: _selectedDate,
                      minimumYear: widget.minYear,
                      maximumYear: widget.maxYear,
                      onDateTimeChanged: (DateTime newDateTime) {
                        setState(() {
                          _selectedDate = newDateTime;
                          _updateTextFieldValue(newDateTime);
                          widget.onDateChanged(newDateTime);
                        });
                      },
                    ),
                  ),
                );
              },
            );
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: GlimpseColors.lightTextField,
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(12),
            ),
            hintStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              color: GlimpseColors.textSubTitle,
              fontWeight: FontWeight.w300,
              fontSize: 16,
            ),
            hintText: widget.hintText ?? _getLocalizedHintText(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(12),
            ),
            suffixIcon: const Padding(
              padding: EdgeInsets.only(right: 0),
              child: Icon(
                IconsaxPlusLinear.calendar,
                size: 24,
                color: GlimpseColors.primaryColorLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
