import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:partiu/screens/chat/widgets/image_lightbox.dart';
import 'package:partiu/screens/chat/widgets/reply_bubble_widget.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// Componente de bolha de mensagem no estilo do Glimpse
class GlimpseChatBubble extends StatelessWidget {

  const GlimpseChatBubble({
    required this.message, required this.isUserSender, required this.time, super.key,
    this.isRead = false,
    this.imageUrl,
    this.isSystem = false,
    this.type,
    this.params,
    this.messageId,
    this.avatarUrl,
    this.fullName,
    this.senderId,
    this.replyTo, // 🆕 Dados de reply
    this.onLongPress, // 🆕 Callback para long press
    this.onReplyTap, // 🆕 Callback para tap no reply
  });
  final String message;
  final bool isUserSender;
  final String time;
  final bool isRead;
  final String? imageUrl;
  final bool isSystem;
  final String? type;
  final Map<String, dynamic>? params;
  final String? messageId;
  final String? avatarUrl;
  final String? fullName;
  final String? senderId;
  final ReplySnapshot? replyTo; // 🆕
  final VoidCallback? onLongPress; // 🆕
  final VoidCallback? onReplyTap; // 🆕

  /// Processa markdown simples (**texto** → negrito)
  List<TextSpan> _parseMarkdown(String text, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    final boldPattern = RegExp(r'\*\*(.+?)\*\*');
    
    var lastMatchEnd = 0;
    
    for (final match in boldPattern.allMatches(text)) {
      // Texto antes do match (normal)
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }
      
      // Texto em negrito
      spans.add(TextSpan(
        text: match.group(1),
        style: baseStyle.copyWith(fontWeight: FontWeight.w700),
      ));
      
      lastMatchEnd = match.end;
    }
    
    // Texto restante após o último match
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }
    
    return spans.isNotEmpty ? spans : [TextSpan(text: text, style: baseStyle)];
  }

  Widget _buildSenderName(BuildContext context) {
    if (isUserSender) return const SizedBox.shrink();

    final style = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: GlimpseColors.textSubTitle,
    );

    if (fullName != null && fullName!.isNotEmpty) {
      return Text(fullName!, style: style);
    }

    if (senderId != null && senderId!.isNotEmpty) {
      return FutureBuilder<Map<String, dynamic>?>(
        future: UserRepository().getUserById(senderId!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final name = snapshot.data!['fullName'] as String? ?? '';
            if (name.isNotEmpty) {
              return Text(name, style: style);
            }
          }
          return const SizedBox.shrink();
        },
      );
    }
    
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final i18n = AppLocalizations.of(context);

    // Traduzir mensagem se for automatizada
    String displayMessage = message;
    if (type == 'automated' && params != null) {
       var template = i18n.translate(message);
       if (template.isNotEmpty) {
         params!.forEach((key, value) {
           template = template.replaceAll('{$key}', value.toString());
         });
         displayMessage = template;
       }
    }
    
    // Definir cores com base no tema e no remetente
  final bubbleColor = isSystem
    ? (isDarkMode
      ? GlimpseColors.lightTextField.withValues(alpha: 0.35)
      : GlimpseColors.lightTextField.withValues(alpha: 0.55))
    : isUserSender
      ? (isDarkMode
        ? GlimpseColors.primaryLight
        : GlimpseColors.primaryLight)
      : (isDarkMode
        ? GlimpseColors.lightTextField
        : GlimpseColors.lightTextField);

  final textColor = isSystem
    ? (isDarkMode
      ? GlimpseColors.textHint
      : GlimpseColors.textSubTitle)
    : isUserSender
      ? GlimpseColors.primaryColorLight
      : (isDarkMode
        ? Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black
        : Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: isSystem
            ? MainAxisAlignment.center
            : (isUserSender ? MainAxisAlignment.end : MainAxisAlignment.start),
        crossAxisAlignment:
            isSystem ? CrossAxisAlignment.center : (isUserSender ? CrossAxisAlignment.end : CrossAxisAlignment.start),
        children: [
          if (!isUserSender && !isSystem) ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(-10 * (1 - value), 0),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: StableAvatar(
                  userId: senderId ?? '',
                  photoUrl: avatarUrl,
                  size: 32,
                  enableNavigation: true,
                ),
              ),
            ),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: isUserSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isUserSender && !isSystem)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: _buildSenderName(context),
                  ),
                // Bolha de mensagem com long press para reply
                GestureDetector(
                  onLongPress: isSystem ? null : onLongPress, // 🆕 Long press para reply (não para system messages)
                  onTap: (imageUrl != null && imageUrl!.isNotEmpty)
                      ? () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder: (context, animation, secondaryAnimation) => ImageLightbox(
                                imageUrl: imageUrl!,
                                heroTag: messageId != null ? 'chatImage_$messageId' : 'chatImage_${imageUrl.hashCode}',
                              ),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                            ),
                          );
                        }
                      : null,
                  child: Container(
                  padding: imageUrl != null && imageUrl!.isNotEmpty
                      ? const EdgeInsets.all(0) // Sem padding para imagens
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: imageUrl != null && imageUrl!.isNotEmpty
                        ? Colors.transparent // Cor transparente para imagens
                        : bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: isSystem
                          ? const Radius.circular(18)
                          : (isUserSender
                              ? const Radius.circular(18)
                              : const Radius.circular(4)),
                      topRight: const Radius.circular(18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: isSystem
                          ? const Radius.circular(18)
                          : (isUserSender
                              ? const Radius.circular(4)
                              : const Radius.circular(18)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🆕 Reply bubble (se for resposta)
                      if (replyTo != null)
                        Padding(
                          padding: imageUrl != null && imageUrl!.isNotEmpty
                              ? const EdgeInsets.fromLTRB(8, 8, 8, 0)
                              : EdgeInsets.zero,
                          child: ReplyBubbleWidget(
                            replySnapshot: replyTo!,
                            isUserSender: isUserSender,
                            onTap: onReplyTap,
                          ),
                        ),
                      
                      // Conteúdo original da mensagem
                      if (imageUrl != null && imageUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              color: GlimpseColors.lightTextField,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Hero(
                              tag: messageId != null ? 'chatImage_$messageId' : 'chatImage_${imageUrl.hashCode}',
                              child: Image.network(
                                imageUrl!,
                                fit: BoxFit.cover,
                                width: 200,
                                height: 200,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 200,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: GlimpseColors.lightTextField,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: CupertinoActivityIndicator(
                                        radius: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 200,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: GlimpseColors.lightTextField,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.image_not_supported, 
                                               color: Colors.grey[600], 
                                               size: 40),
                                          const SizedBox(height: 8),
                                          Text(
                                            i18n.translate('failed_to_load_image'),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        )
                      else
                        Text.rich(
                          TextSpan(
                            children: _parseMarkdown(
                              displayMessage,
                              GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                                fontSize: isSystem ? 13 : 16,
                                fontWeight:
                                    isSystem ? FontWeight.w600 : FontWeight.w400,
                                letterSpacing: isSystem ? 0.2 : 0.0,
                                color: textColor,
                              ),
                            ),
                          ),
                          textAlign: isSystem ? TextAlign.center : TextAlign.left,
                        ),
                    ],
                  ),
                ),
                ),
                
                // Horário (não exibido para system)
                if (!isSystem)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                    child: Text(
                      time,
                      style: GlimpseStyles.smallTextStyle(
                        color: GlimpseColors.textSubTitle,
                      ).copyWith(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          
          if (isUserSender && !isSystem) ...[
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
