import 'package:flutter/material.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget de seleção de país usando flutter_country_selector
class CountrySelectorWidget extends StatefulWidget {
  const CountrySelectorWidget({
    required this.initialCountry,
    required this.onCountryChanged,
    super.key,
  });

  final String? initialCountry;
  final ValueChanged<CountryData?> onCountryChanged;

  @override
  State<CountrySelectorWidget> createState() => _CountrySelectorWidgetState();
}

class _CountrySelectorWidgetState extends State<CountrySelectorWidget> {
  IsoCode? _selectedCountryCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_selectedCountryCode != null) return;

    final initial = widget.initialCountry?.trim();
    if (initial == null || initial.isEmpty) return;

    final localization = CountrySelectorLocalization.of(context);
    if (localization == null) return;

    final normalized = initial.toLowerCase();
    for (final code in IsoCode.values) {
      final name = localization.countryName(code).toLowerCase();
      if (name == normalized) {
        _selectedCountryCode = code;
        break;
      }
    }
  }

  void _showCountryPicker() {
    final appLocale = Localizations.localeOf(context);
    // O pacote flutter_country_selector suporta locales sem region (ex: `pt`, `en`, `es`).
    // Nosso app usa `pt_BR`/`en_US`/`es_ES`, então forçamos o selector a usar só o languageCode.
    final selectorLocale = Locale(appLocale.languageCode);

    final mediaQuery = MediaQuery.of(context);
    final appBarHeight = Scaffold.maybeOf(context)?.appBarMaxHeight ?? kToolbarHeight;
    final maxSheetHeight = mediaQuery.size.height - (mediaQuery.padding.top + appBarHeight);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: GlimpseColors.bgColorLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxHeight: maxSheetHeight,
      ),
      builder: (sheetContext) {
        return Localizations.override(
          context: sheetContext,
          locale: selectorLocale,
          child: Builder(
            builder: (localizedContext) {
              final selectorI18n = CountrySelectorLocalization.of(localizedContext);

              return SafeArea(
                top: false,
                child: CountrySelector.sheet(
                  showDialCode: false,
                  flagSize: 24.sp,
                  searchBoxIconColor: GlimpseColors.textSubTitle,
                  searchBoxTextStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    color: GlimpseColors.primaryColorLight,
                    fontWeight: FontWeight.w400,
                    fontSize: 14.sp,
                    height: 1.4,
                  ),
                  searchBoxDecoration: InputDecoration(
                    hintText: selectorI18n?.search ?? 'Search',
                    hintStyle: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      color: GlimpseColors.textSubTitle,
                      fontWeight: FontWeight.w400,
                      fontSize: 14.sp,
                      height: 1.4,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20.sp,
                      color: GlimpseColors.textSubTitle,
                    ),
                    filled: true,
                    fillColor: GlimpseColors.lightTextField,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 16.h,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  titleStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    color: GlimpseColors.primaryColorLight,
                    fontWeight: FontWeight.w400,
                    fontSize: 14.sp,
                    height: 1.4,
                  ),
                  onCountrySelected: (code) {
                    setState(() => _selectedCountryCode = code);

                    widget.onCountryChanged(
                      CountryData(
                        name: _countryName(code),
                        flag: _flagEmojiFromIso(code),
                      ),
                    );

                    Navigator.of(sheetContext).pop();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _countryName(IsoCode code) {
    final localization = CountrySelectorLocalization.of(context);
    if (localization == null) return code.name;
    return localization.countryName(code);
  }

  String _flagEmojiFromIso(IsoCode code) {
    final iso = code.name.toUpperCase();
    if (iso.length != 2) return '';

    const base = 0x1F1E6;
    return String.fromCharCodes(
      iso.codeUnits.map((c) => base + (c - 0x41)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return GestureDetector(
      onTap: _showCountryPicker,
      child: Container(
        height: 56.h,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        decoration: BoxDecoration(
          color: GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            if (_selectedCountryCode != null) ...[
              Text(
                _flagEmojiFromIso(_selectedCountryCode!),
                style: TextStyle(fontSize: 20.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  _countryName(_selectedCountryCode!),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w400,
                    color: GlimpseColors.primaryColorLight,
                    height: 1.4,
                  ),
                ),
              ),
            ] else
              Expanded(
                child: Text(
                  i18n.translate('select_country'),
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w400,
                    color: GlimpseColors.textSubTitle,
                    height: 1.4,
                  ),
                ),
              ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16.sp,
              color: GlimpseColors.textSubTitle,
            ),
          ],
        ),
      ),
    );
  }
}

/// Classe para transferir dados do país selecionado
class CountryData {
  final String name;
  final String flag;

  CountryData({
    required this.name,
    required this.flag,
  });
}

