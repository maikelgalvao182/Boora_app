import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:circle_flags/circle_flags.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Widget de seleção de país
/// Usa flutter_country_selector para lista completa de países
class CountrySelectorWidget extends StatefulWidget {
  const CountrySelectorWidget({
    required this.initialCountry,
    required this.onCountryChanged,
    super.key,
  });

  final String? initialCountry;
  final ValueChanged<String?> onCountryChanged;

  @override
  State<CountrySelectorWidget> createState() => _CountrySelectorWidgetState();
}

class _CountrySelectorWidgetState extends State<CountrySelectorWidget> {
  IsoCode? _selectedCountry;

  @override
  void initState() {
    super.initState();
    // Carrega o país inicial se fornecido
    if (widget.initialCountry != null && widget.initialCountry!.isNotEmpty) {
      try {
        // Tenta encontrar o IsoCode baseado no código do país (ex: "BR", "US")
        _selectedCountry = IsoCode.values.firstWhere(
          (isoCode) => isoCode.name == widget.initialCountry!.toUpperCase(),
          orElse: () => IsoCode.BR, // Default para Brasil
        );
      } catch (e) {
        _selectedCountry = null;
      }
    }
  }

  Future<void> _showCountryPicker() async {
    HapticFeedback.lightImpact();
    
    final isoCode = await showModalBottomSheet<IsoCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: CountrySelector.sheet(
          onCountrySelected: (isoCode) => Navigator.of(context).pop(isoCode),
          favoriteCountries: const [IsoCode.BR, IsoCode.US],
          addFavoritesSeparator: true,
          searchBoxDecoration: InputDecoration(
            hintText: 'Buscar país...',
            hintStyle: const TextStyle(
              fontFamily: FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              color: GlimpseColors.textSubTitle,
            ),
            filled: true,
            fillColor: GlimpseColors.lightTextField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: GlimpseColors.primary,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            prefixIcon: const Icon(
              Icons.search,
              color: GlimpseColors.textSubTitle,
            ),
          ),
          searchBoxTextStyle: const TextStyle(
            fontFamily: FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            color: GlimpseColors.textSubTitle,
          ),
        ) as Widget,
      ) as Widget,
    );
    
    if (isoCode != null) {
      setState(() {
        _selectedCountry = isoCode;
      });
      // IsoCode.name retorna o código do país (ex: "BR", "US")
      widget.onCountryChanged(isoCode.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    const borderRadius = 12.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            i18n.translate('country_label'),
            style: GlimpseStyles.fieldLabelStyle(
              color: Theme.of(context).textTheme.titleMedium?.color,
            ),
          ),
        ),
        
        // Campo clicável
        GestureDetector(
          onTap: _showCountryPicker,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: GlimpseColors.lightTextField,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Flag e nome do país selecionado
                if (_selectedCountry != null) ...[
                  CircleFlag(
                    _selectedCountry!.name,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      CountrySelectorLocalization.of(context)?.countryName(_selectedCountry!) ?? _selectedCountry!.name,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        color: GlimpseColors.textSubTitle,
                        fontWeight: FontWeight.w400,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                ] else ...[
                  // Placeholder
                  Expanded(
                    child: Text(
                      i18n.translate('select_country'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        color: GlimpseColors.textSubTitle,
                        fontWeight: FontWeight.w300,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                
                // Ícone de dropdown
                Icon(
                  Icons.keyboard_arrow_down,
                  color: GlimpseColors.textSubTitle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
