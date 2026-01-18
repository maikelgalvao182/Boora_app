import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Card para exibir usuário bloqueado
/// 
/// Exibe:
/// - Avatar (StableAvatar)
/// - fullName
/// - from (localização)
/// - Botão "Desbloquear" com fundo vermelho claro
class BlockedUserCard extends StatelessWidget {
  const BlockedUserCard({
    required this.userId,
    required this.fullName,
    required this.onUnblock,
    this.from,
    this.photoUrl,
    super.key,
  });

  final String userId;
  final String fullName;
  final String? from;
  final String? photoUrl;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final unblockLabel = i18n.translate('unblock');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          StableAvatar(
            userId: userId,
            photoUrl: photoUrl,
            size: 58,
            borderRadius: BorderRadius.circular(8),
            enableNavigation: false, // Desabilitado para usuários bloqueados
          ),
          
          const SizedBox(width: 12),
          
          // Informações
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Nome completo
                ReactiveUserNameWithBadge(
                  userId: userId,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
                
                // Localização
                if (from != null && from!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    from!,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GlimpseColors.textSubTitle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Botão Desbloquear
          TextButton(
            onPressed: onUnblock,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: const Color(0xFFFFEBEE), // Vermelho clarinho
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              unblockLabel.isNotEmpty ? unblockLabel : 'Desbloquear',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.dangerRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
