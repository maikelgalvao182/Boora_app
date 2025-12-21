import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/verification/didit_verification_screen.dart';

/// Card compartilhado para promover verificação de perfil
/// 
/// Abre automaticamente a tela de verificação de identidade ao ser clicado
class VerificationCard extends StatelessWidget {
  const VerificationCard({
    super.key,
    this.onTap,
    this.onVerificationComplete,
  });

  /// Callback customizado (opcional) - executado em vez do fluxo padrão
  final VoidCallback? onTap;
  
  /// Callback chamado após verificação bem-sucedida
  final VoidCallback? onVerificationComplete;

  /// Abre a tela de verificação de identidade
  Future<void> _openVerification(BuildContext context) async {
    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => const DiditVerificationScreen(),
        ),
      );

      // Se verificação foi concluída com sucesso
      if (result == true && context.mounted) {
        onVerificationComplete?.call();
      }
    } catch (e) {
      if (context.mounted) {
        final i18n = AppLocalizations.of(context);
        ToastService.showError(
          message: i18n.translate('error_opening_verification'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          
          // Se há callback customizado, usa ele; senão, abre verificação
          if (onTap != null) {
            onTap!();
          } else {
            _openVerification(context);
          }
        },
        child: Container(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: GlimpseColors.primaryColorLight,
          ),
          child: const Stack(
            children: [
              // Ícone decorativo atrás (ordem anterior para ficar no fundo)
              _BackgroundIcon(),
              // Conteúdo principal acima do ícone
              Padding(
                padding: EdgeInsets.all(16),
                child: _CardContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conteúdo textual do card de verificação
class _CardContent extends StatelessWidget {
  const _CardContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Seja verificado',
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Verifique seu perfil e conquiste a confiança das pessoas',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Espaço reservado para o ícone
        const SizedBox(width: 96), // 80 (width do SVG) + 16 (padding right)
      ],
    );
  }
}



/// Ícone de fundo decorativo do card
class _BackgroundIcon extends StatelessWidget {
  const _BackgroundIcon();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 16,
      bottom: 16,
      child: SvgPicture.asset(
        'assets/svg/face.svg',
        width: 70,
        height: 70,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(
          Colors.white,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
