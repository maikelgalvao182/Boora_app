import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';

/// Widget que mostra preview da mensagem sendo respondida
/// 
/// Aparece acima do input de texto quando o usuário inicia um reply.
/// Mostra:
/// - Linha vertical colorida (azul para próprio, cinza para outros)
/// - Nome do autor
/// - Preview do texto/imagem (já truncado)
/// - Botão X para cancelar
class ReplyPreviewWidget extends StatelessWidget {
  const ReplyPreviewWidget({
    required this.replySnapshot,
    required this.onCancel,
    required this.isOwnMessage,
    super.key,
  });

  /// Dados da mensagem sendo respondida
  final ReplySnapshot replySnapshot;
  
  /// Callback quando usuário cancela o reply (clica no X)
  final VoidCallback onCancel;
  
  /// Se true, a mensagem sendo respondida é do próprio usuário
  final bool isOwnMessage;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Cor de fundo
    final backgroundColor = isDarkMode
        ? GlimpseColors.lightTextField.withValues(alpha: 0.3)
        : GlimpseColors.lightTextField.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Linha vertical colorida (handle)
          Container(
            width: 4,
            height: 56,
            decoration: const BoxDecoration(
              color: GlimpseColors.primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          
          // Ícone de reply
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(
              Iconsax.repeat,
              size: 18,
              color: GlimpseColors.primary,
            ),
          ),
          
          // Conteúdo do preview
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nome do autor
                  Text(
                    replySnapshot.senderName,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GlimpseColors.primaryDarker,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 2),
                  
                  // Preview do conteúdo
                  _buildContentPreview(context),
                ],
              ),
            ),
          ),
          
          // Botão de cancelar
          IconButton(
            onPressed: onCancel,
            icon: Icon(
              Iconsax.close_circle,
              size: 22,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPreview(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
    
    // Se for imagem
    if (replySnapshot.type == 'image' || replySnapshot.imageUrl != null) {
      return Text(
        replySnapshot.text ?? 'Foto',
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textColor.withValues(alpha: 0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    
    // Texto normal
    return Text(
      replySnapshot.text ?? '',
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textColor.withValues(alpha: 0.7),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
