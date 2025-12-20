import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';

/// Widget que renderiza a referência de reply dentro de uma bolha de mensagem
/// 
/// Aparece acima do texto principal da mensagem quando é uma resposta.
/// Mostra:
/// - Borda esquerda colorida (3px)
/// - Nome do autor
/// - Texto ou indicador de tipo (📷 Foto, 🎤 Áudio)
/// - Thumbnail de imagem 40x40 (se houver)
/// - Ripple effect ao tocar
class ReplyBubbleWidget extends StatelessWidget {
  const ReplyBubbleWidget({
    required this.replySnapshot,
    required this.isUserSender,
    this.onTap,
    super.key,
  });

  /// Dados do reply
  final ReplySnapshot replySnapshot;
  
  /// Se true, quem enviou a mensagem atual é o usuário local
  final bool isUserSender;
  
  /// Callback quando toca no reply (scroll para mensagem original)
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Cor da linha lateral - azul se o reply é de mensagem própria
    final lineColor = GlimpseColors.primaryLight;
    
    // Cor de fundo do reply bubble
    final backgroundColor = isUserSender
        ? (isDarkMode 
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.5))
        : (isDarkMode
            ? Colors.black.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.08));

    // Cor do texto
    final textColor = isUserSender
        ? GlimpseColors.primaryColorLight
        : (isDarkMode ? Colors.white : Colors.black87);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Linha vertical colorida
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: lineColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
              
              // Conteúdo
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nome do autor
                      Text(
                        replySnapshot.senderName,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: lineColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 2),
                      
                      // Conteúdo do reply
                      _buildContent(textColor),
                    ],
                  ),
                ),
              ),
              
              // Thumbnail de imagem (se houver)
              if (replySnapshot.imageUrl != null && replySnapshot.imageUrl!.isNotEmpty)
                _buildImageThumbnail(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color textColor) {
    // Se for mensagem de imagem sem texto
    if (replySnapshot.type == 'image' && (replySnapshot.text == null || replySnapshot.text!.isEmpty)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Iconsax.image,
            size: 14,
            color: textColor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'Foto',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }
    
    // Se for áudio
    if (replySnapshot.type == 'audio') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Iconsax.microphone,
            size: 14,
            color: textColor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'Áudio',
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }
    
    // Texto normal
    return Text(
      replySnapshot.text ?? '',
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: textColor.withValues(alpha: 0.8),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildImageThumbnail() {
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          replySnapshot.imageUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Iconsax.image,
                size: 20,
                color: Colors.grey[500],
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
