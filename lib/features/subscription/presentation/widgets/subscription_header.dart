import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';

/// Header do dialog de assinatura VIP
/// 
/// Responsabilidades:
/// - Exibir imagem de fundo
/// - Mostrar título "Wedconnex Pro"
/// - Mostrar subtítulo com benefícios
/// - Botão de fechar no canto superior direito
/// 
/// Uso:
/// ```dart
/// SubscriptionHeader(
///   onClose: () => Navigator.of(context).pop(),
/// )
/// ```
class SubscriptionHeader extends StatelessWidget {

  const SubscriptionHeader({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Stack(
      children: [
        // Container sem imagem de fundo
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.asset(
                  'assets/images/simbolo.png',
                  height: 70,
                  width: 70,
                ),
              ),
                            
              // Título principal
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  i18n.translate('wedconnex_pro'),
                  style: const TextStyle(
                    fontFamily: FONT_PLUS_JAKARTA_SANS,
                    fontSize: 20,
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Subtítulo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  i18n.translate('take_advantage_of_the_benefits_of_being_a_pro'),
                  style: const TextStyle(
                    fontFamily: FONT_PLUS_JAKARTA_SANS,
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
