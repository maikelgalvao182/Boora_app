import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';

/// Widget de seleção de origem (onde conheceu o app)
/// Extraído de TelaOrigem para reutilização no wizard
class OriginSelectorWidget extends StatefulWidget {
  const OriginSelectorWidget({
    required this.initialOrigin,
    required this.onOriginChanged,
    super.key,
  });

  final String? initialOrigin;
  final ValueChanged<String?> onOriginChanged;

  @override
  State<OriginSelectorWidget> createState() => _OriginSelectorWidgetState();
}

class _OriginSelectorWidgetState extends State<OriginSelectorWidget> {
  String? _selected;

  final List<String> _options = const [
    'Instagram',
    'Tiktok',
    'Threads',
    'Reddit',
    'Youtube',
    'X',
    'App Store',
    'Facebook',
    'Linkedin',
    'Google',
    'Website',
    'Friend / Family',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialOrigin;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    final localizedOptions = <String>[
      'Instagram',
      'Tiktok',
      'Threads',
      'Reddit',
      'Youtube',
      'X',
      'App Store',
      'Facebook',
      'Linkedin',
      'Google',
      'Website',
      i18n.translate('origin_friend_family'),
      i18n.translate('origin_other'),
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ...List.generate(_options.length, (index) {
          final option = _options[index];
          final label = localizedOptions[index];
          final selected = option == _selected;
          final iconName = _mapOriginOptionToIcon(option.toLowerCase());
          
          return Padding(
            padding: EdgeInsets.only(bottom: index < _options.length - 1 ? 14 : 0),
            child: _OriginOptionTile(
              text: label,
              selected: selected,
              iconName: iconName,
              onTap: () {
                setState(() => _selected = option);
                widget.onOriginChanged(option);
              },
            ),
          );
        }),
      ],
    );
  }

  /// Mapeia opções para ícones
  String? _mapOriginOptionToIcon(String label) {
    if (label.contains('instagram')) return 'instagram';
    if (label.contains('tiktok')) return 'tiktok';
    if (label.contains('threads')) return 'threads';
    if (label.contains('reddit')) return 'reedit';
    if (label.contains('youtube')) return 'youtube';
    if (label == 'x') return 'x';
    if (label.contains('app store') || label.contains('appstore') || label == 'app store') {
      return 'appstore';
    }
    if (label.contains('facebook')) return 'facebook';
    if (label.contains('linkedin')) return 'linkedin';
    if (label.contains('google')) return 'google';
    if (label.contains('website')) return 'iconsax:global';
    if (label.contains('friend') || label.contains('family')) return 'iconsax:people';
    if (label.contains('other')) return 'iconsax:more';
    return null;
  }
}

/// Tile de opção de origem
class _OriginOptionTile extends StatelessWidget {
  const _OriginOptionTile({
    required this.text,
    required this.selected,
    required this.onTap,
    this.iconName,
  });

  final String text;
  final bool selected;
  final String? iconName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 54,
        decoration: BoxDecoration(
          // Apenas o selecionado fica branco; outros usam lightTextField
          color: selected ? Colors.white : GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? GlimpseColors.primary : GlimpseColors.lightTextField,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // Ícone da opção
            if (iconName != null) ...[
              if (iconName!.startsWith('iconsax:'))
                Icon(
                  _getIconsaxIcon(iconName!),
                  size: 20,
                  color: Colors.black,
                )
              else if (iconName == 'appstore')
                Image.asset(
                  'assets/images/appstore.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                )
              else
                SvgPicture.asset(
                  'assets/svg/$iconName.svg',
                  width: 20,
                  height: 20,
                ),
              const SizedBox(width: 12),
            ],
            
            // Texto da opção
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconsaxIcon(String iconName) {
    switch (iconName) {
      case 'iconsax:global':
        return IconsaxPlusLinear.global;
      case 'iconsax:people':
        return IconsaxPlusLinear.people;
      case 'iconsax:more':
        return IconsaxPlusLinear.more;
      default:
        return IconsaxPlusLinear.global;
    }
  }
}
