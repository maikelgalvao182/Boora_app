import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/stores/user_store.dart';

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
    final i18n = AppLocalizations.of(context);
    
    // Cor da linha lateral - azul se o reply é de mensagem própria
    final lineColor = GlimpseColors.primaryLight;
    
    // Cor de fundo do reply bubble
    final backgroundColor = GlimpseColors.primaryLight;

    // Cor do texto
    final textColor = isUserSender
        ? GlimpseColors.primaryColorLight
        : (isDarkMode ? Colors.white : Colors.black87);

    final senderNameStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    );

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
                      _buildSenderName(context, senderNameStyle),
                      
                      const SizedBox(height: 2),
                      
                      // Conteúdo do reply
                      _buildContent(i18n, textColor),
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

  Widget _buildContent(AppLocalizations i18n, Color textColor) {
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
            i18n.translate('photo'),
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
            i18n.translate('audio'),
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
        child: Builder(
          builder: (context) {
            final url = replySnapshot.imageUrl!;
            final key = stableImageCacheKey(url);
            ImageCacheStats.instance.record(
              category: ImageCacheCategory.chatMedia,
              url: url,
              cacheKey: key,
            );

            return CachedNetworkImage(
              imageUrl: url,
              cacheManager: ChatMediaImageCache.instance,
              cacheKey: key,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (context, _) {
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorWidget: (context, _, __) {
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildSenderName(BuildContext context, TextStyle style) {
    final resolvedSenderId = replySnapshot.senderId.trim();
    final snapshotName = replySnapshot.senderName.trim();

    // Se não temos senderId, só dá para usar o que veio no snapshot.
    if (resolvedSenderId.isEmpty) {
      if (snapshotName.isEmpty || _isPlaceholderName(snapshotName)) {
        return const SizedBox.shrink();
      }
      return Text(
        _formatDisplayName(snapshotName),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final notifier = UserStore.instance.getNameNotifier(resolvedSenderId);
    return ValueListenableBuilder<String?>(
      valueListenable: notifier,
      builder: (context, name, _) {
        final storeName = name?.trim() ?? '';
        if (storeName.isNotEmpty && !_isPlaceholderName(storeName)) {
          return Text(
            _formatDisplayName(storeName),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Fallback raro: tenta query direta apenas se ainda não temos nada.
        return FutureBuilder<Map<String, dynamic>?>(
          future: UserRepository().getUserById(resolvedSenderId),
          builder: (context, snapshot) {
            final data = snapshot.data;
            final fetched = (data?['fullName'] as String?)?.trim() ??
                (data?['fullname'] as String?)?.trim() ??
                '';

            if (fetched.isEmpty || _isPlaceholderName(fetched)) {
              // Sem nome resolvido: tenta usar o snapshot se ele não for placeholder.
              if (snapshotName.isNotEmpty && !_isPlaceholderName(snapshotName)) {
                return Text(
                  _formatDisplayName(snapshotName),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              }

              return const SizedBox.shrink();
            }

            return Text(
              _formatDisplayName(fetched),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        );
      },
    );
  }

  String _formatDisplayName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Usuário';

    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Usuário';

    final first = parts.first;
    if (parts.length == 1) {
      return first.length > 15 ? first.substring(0, 15) : first;
    }

    final lastInitial = parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
    final safeFirst = first.length > 15 ? first.substring(0, 15) : first;
    return lastInitial.isEmpty ? safeFirst : '$safeFirst $lastInitial.';
  }

  bool _isPlaceholderName(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'unknown user' ||
        normalized == 'unkonwn user' ||
        normalized == 'unknow user' ||
        normalized == 'usuário' ||
        normalized == 'usuario';
  }
}
