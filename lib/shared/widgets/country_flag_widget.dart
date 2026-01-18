import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';

/// Widget compartilhável que exibe a bandeira do país
/// 
/// Aparece como um círculo com a flag emoji e borda branca
/// Usado em avatares e cards de perfil
class CountryFlagWidget extends StatelessWidget {
  const CountryFlagWidget({
    this.countryName,
    this.flag,
    this.size = 24,
    this.borderWidth = 2,
    super.key,
  });

  final String? countryName;
  final String? flag;
  final double size;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final origin = countryName?.trim() ?? '';
    final isoCode = _resolveIsoCode(context, origin);
    final emojiFlag = flag?.trim() ?? '';
    final canShowEmoji = emojiFlag.isNotEmpty;

    if ((isoCode == null || isoCode.isEmpty) && !canShowEmoji) {
      return const SizedBox.shrink();
    }

    return Container(
      width: size * 1.6,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white,
          width: borderWidth,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: isoCode != null && isoCode.isNotEmpty
            ? SizedBox.expand(
                child: SvgPicture.asset(
                  'assets/svg/${isoCode.toLowerCase()}.svg',
                  package: 'circle_flags',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              )
            : Center(
                child: Text(
                  emojiFlag,
                  style: TextStyle(
                    fontSize: size * 0.85,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }

  String? _resolveIsoCode(BuildContext context, String country) {
    final normalized = country.trim();
    if (normalized.isEmpty) return null;

    // Se já vier como código ISO (BR/US/...), usa direto.
    if (normalized.length == 2) {
      final upper = normalized.toUpperCase();
      final isValid = IsoCode.values.any((code) => code.name.toUpperCase() == upper);
      return isValid ? upper : null;
    }

    // 1) Tenta resolver pelo map rápido (nomes mais comuns).
    final quick = getCountryInfo(normalized)?.flagCode;
    if (quick != null && quick.isNotEmpty) return quick;

    // 2) Resolve pelos nomes localizados do pacote no locale atual.
    final localization = CountrySelectorLocalization.of(context);
    if (localization != null) {
      final target = normalized.toLowerCase();
      for (final iso in IsoCode.values) {
        if (localization.countryName(iso).toLowerCase() == target) {
          return iso.name;
        }
      }
    }

    // 3) Fallback técnico: inglês do pacote (export público).
    final en = CountrySelectorLocalizationEn();
    final target = normalized.toLowerCase();
    for (final iso in IsoCode.values) {
      if (en.countryName(iso).toLowerCase() == target) {
        return iso.name;
      }
    }

    return null;
  }
}
