import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/screens/chat/models/reply_snapshot.dart';
import 'package:partiu/screens/chat/widgets/image_lightbox.dart';
import 'package:partiu/screens/chat/widgets/reply_bubble_widget.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/cache/cache_key_utils.dart';
import 'package:partiu/core/services/cache/image_caches.dart';
import 'package:partiu/core/services/cache/image_cache_stats.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

/// Componente de bolha de mensagem no estilo do Glimpse
class GlimpseChatBubble extends StatelessWidget {

  static final Map<String, Future<_LinkPreviewData?>> _linkPreviewCache = {};

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
    this.onDelete, // 🆕 Callback para deletar mensagem
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
  final Future<void> Function()? onDelete; // 🆕

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

  String? _extractFirstUrl(String text) {
    final urlPattern = RegExp(
      r'(?:(?:https?:\/\/)|(?:www\.))[^\s<>()]+',
      caseSensitive: false,
    );
    final match = urlPattern.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(0)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Uri? _toLaunchableUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\/').hasMatch(trimmed);
    final normalized = hasScheme ? trimmed : 'https://$trimmed';
    return Uri.tryParse(normalized);
  }

  Future<_LinkPreviewData?> _fetchLinkPreview(Uri url) async {
    try {
      final applePreview = await _tryFetchAppleAppStorePreview(url);
      if (applePreview != null) return applePreview;

      final response = await http
          .get(
            url,
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Mobile; Partiu) AppleWebKit/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode < 200 || response.statusCode >= 400) return null;
    final html = _decodeHtmlResponse(response);
      if (html.isEmpty) return null;

      String? metaContent(String propertyOrName) {
        final escaped = RegExp.escape(propertyOrName);

        final propertyRegex = RegExp(
          '<meta[^>]+property=["\']$escaped["\'][^>]+content=["\']([^"\']+)["\'][^>]*>',
          caseSensitive: false,
        );
        final nameRegex = RegExp(
          '<meta[^>]+name=["\']$escaped["\'][^>]+content=["\']([^"\']+)["\'][^>]*>',
          caseSensitive: false,
        );

        final propertyMatch = propertyRegex.firstMatch(html);
        if (propertyMatch != null) return propertyMatch.group(1)?.trim();
        final nameMatch = nameRegex.firstMatch(html);
        return nameMatch?.group(1)?.trim();
      }

      String? title = metaContent('og:title') ?? metaContent('twitter:title');
      String? description = metaContent('og:description') ?? metaContent('twitter:description');
      String? image = metaContent('og:image') ?? metaContent('twitter:image');

      if (title != null && title.isNotEmpty) {
        title = _repairMojibake(_decodeHtmlEntities(title));
      }
      if (description != null && description.isNotEmpty) {
        description = _repairMojibake(_decodeHtmlEntities(description));
      }

      if ((title == null || title.isEmpty)) {
        final titleRegex = RegExp('<title[^>]*>([^<]+)<\\/title>', caseSensitive: false);
        title = titleRegex.firstMatch(html)?.group(1)?.trim();
        if (title != null && title.isNotEmpty) {
          title = _repairMojibake(_decodeHtmlEntities(title));
        }
      }

      Uri? resolvedImage;
      final imageUri = image != null ? Uri.tryParse(image) : null;
      if (imageUri != null) {
        resolvedImage = imageUri.hasScheme ? imageUri : url.resolveUri(imageUri);
      }

      if ((title == null || title.isEmpty) &&
          (description == null || description.isEmpty) &&
          resolvedImage == null) {
        return null;
      }

      return _LinkPreviewData(
        url: url,
        title: title,
        description: description,
        imageUrl: resolvedImage?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  String _decodeHtmlEntities(String input) {
    var value = input;
    value = value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');

    // Entidades numéricas: &#123; e &#x1F60A;
    value = value.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      if (code == null) return m.group(0) ?? '';
      return String.fromCharCode(code);
    });
    value = value.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      if (code == null) return m.group(0) ?? '';
      return String.fromCharCode(code);
    });

    return value;
  }

  String _repairMojibake(String value) {
    final looksBroken = value.contains('Ã') ||
        value.contains('Â') ||
        value.contains('â€') ||
        value.contains('â™') ||
        value.contains('â€“') ||
        value.contains('â€”');
    if (!looksBroken) return value;

    try {
      return utf8.decode(latin1.encode(value), allowMalformed: true);
    } catch (_) {
      return value;
    }
  }

  Future<_LinkPreviewData?> _tryFetchAppleAppStorePreview(Uri url) async {
    final host = url.host.toLowerCase();
    if (host != 'apps.apple.com') return null;

    final parsed = _extractAppleAppIdAndCountry(url);
    if (parsed == null) return null;

    final (appId, country) = parsed;
    final lookupUrl = Uri.parse('https://itunes.apple.com/lookup?id=$appId&country=$country');

    try {
      final res = await http
          .get(
            lookupUrl,
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Mobile; Partiu) AppleWebKit/537.36',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode < 200 || res.statusCode >= 400) return null;

      final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) return null;

      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map) return null;

      final trackName = (first['trackName'] as String?)?.trim();
      final sellerName = (first['sellerName'] as String?)?.trim();
      final artworkUrl = (first['artworkUrl512'] as String?)?.trim() ??
          (first['artworkUrl100'] as String?)?.trim() ??
          (first['artworkUrl60'] as String?)?.trim();
      final trackViewUrl = (first['trackViewUrl'] as String?)?.trim();

      final openUrl = Uri.tryParse(trackViewUrl ?? '') ?? url;

      return _LinkPreviewData(
        url: openUrl,
        title: trackName,
        description: sellerName,
        imageUrl: artworkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  (String appId, String country)? _extractAppleAppIdAndCountry(Uri url) {
    final idMatch = RegExp(r'\bid(\d+)\b', caseSensitive: false).firstMatch(url.path);
    final appId = idMatch?.group(1);
    if (appId == null || appId.isEmpty) return null;

    // apps.apple.com/{country}/app/.../id123
    String country = 'br';
    if (url.pathSegments.isNotEmpty) {
      final candidate = url.pathSegments.first.toLowerCase();
      if (RegExp(r'^[a-z]{2}$').hasMatch(candidate)) {
        country = candidate;
      }
    }

    return (appId, country);
  }

  String _decodeHtmlResponse(http.Response response) {
    try {
      // ✅ Força decode UTF-8 (evita AppÂ / â€¦ em links comuns)
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
  }

  Future<_LinkPreviewData?> _getLinkPreview(Uri url) {
    final key = url.toString();
    if (kDebugMode) {
      // Evita cache enganando durante hot reload.
      _linkPreviewCache.remove(key);
    }
    return _linkPreviewCache.putIfAbsent(key, () => _fetchLinkPreview(url));
  }

  Future<void> _openUrl(Uri url) async {
    if (!await canLaunchUrl(url)) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _showMessageActionsSheet(
    BuildContext context, {
    required AppLocalizations i18n,
    required String messageText,
    required bool canReply,
    required VoidCallback? onReply,
    required bool canDelete,
    required Future<void> Function()? onDelete,
  }) async {
    final rootContext = context;
    final resolvedText = messageText.trim();
    final canCopy = resolvedText.isNotEmpty;

    if (!canReply && !canCopy && !canDelete) return;

    final replyLabel = i18n.translate('reply');
    final copyLabel = i18n.translate('copy');
    final copiedLabel = i18n.translate('copied');
    final deleteLabel = i18n.translate('delete');

    await showCupertinoModalPopup<void>(
      context: rootContext,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          actions: [
            if (canReply)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onReply?.call();
                },
                child: Text(replyLabel),
              ),
            if (canCopy)
              CupertinoActionSheetAction(
                onPressed: () async {
                  final navigator = Navigator.of(sheetContext);

                  await Clipboard.setData(ClipboardData(text: resolvedText));

                  if (!sheetContext.mounted || !rootContext.mounted) return;
                  navigator.pop();

                  ToastService.showInfo(
                    message: copiedLabel,
                    duration: const Duration(seconds: 2),
                  );
                },
                child: Text(copyLabel),
              ),
            if (canDelete)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () async {
                  final navigator = Navigator.of(sheetContext);
                  navigator.pop();
                  await onDelete?.call();
                },
                child: Text(deleteLabel),
              ),
          ],
          // Sem botão "Cancelar" (pedido do usuário). Dismiss ao tocar fora.
          cancelButton: null,
        );
      },
    );
  }

  Widget _buildLinkPreviewCard(BuildContext context, Uri url) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final titleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: isDarkMode
          ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
          : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
    );
    final descStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: GlimpseColors.textSubTitle,
    );
    final urlStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: GlimpseColors.textHint,
    );

    return FutureBuilder<_LinkPreviewData?>(
      future: _getLinkPreview(url),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();

        final hasImage = (data.imageUrl ?? '').trim().isNotEmpty;
        final resolvedTitle = (data.title ?? '').trim();
        final resolvedDesc = (data.description ?? '').trim();

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openUrl(data.url),
            child: Container(
              decoration: BoxDecoration(
                color: GlimpseColors.bgColorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasImage)
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: data.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, _) => Container(
                          color: GlimpseColors.bgColorLight,
                          child: Center(
                            child: CupertinoActivityIndicator(
                              radius: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                        errorWidget: (context, _, __) => Container(
                          color: GlimpseColors.bgColorLight,
                          child: Center(
                            child: Icon(Icons.link, color: Colors.grey[600], size: 28),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (resolvedTitle.isNotEmpty)
                          Text(
                            resolvedTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        if (resolvedTitle.isNotEmpty && resolvedDesc.isNotEmpty)
                          const SizedBox(height: 6),
                        if (resolvedDesc.isNotEmpty)
                          Text(
                            resolvedDesc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: descStyle,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          data.url.host.isNotEmpty ? data.url.host : data.url.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: urlStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSenderName(BuildContext context) {
    if (isUserSender) return const SizedBox.shrink();

    final style = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: GlimpseColors.textSubTitle,
    );

    final resolvedSenderId = senderId?.trim() ?? '';
    if (resolvedSenderId.isNotEmpty) {
      final notifier = UserStore.instance.getNameNotifier(resolvedSenderId);
      return ValueListenableBuilder<String?>(
        valueListenable: notifier,
        builder: (context, name, _) {
          // Prioridade: display name resolvido (fonte única) via UserStore.
          final resolvedName = name?.trim() ?? '';
          if (resolvedName.isNotEmpty && !_isPlaceholderName(resolvedName)) {
            return Text(resolvedName, style: style);
          }

          // Fallback 1 (se veio no payload local da msg, por ex. cache):
          final resolvedFullName = fullName?.trim() ?? '';
          if (resolvedFullName.isNotEmpty && !_isPlaceholderName(resolvedFullName)) {
            return Text(resolvedFullName, style: style);
          }

          // Fallback 2 (raro): tenta query direta apenas se ainda não temos nada.
          return FutureBuilder<Map<String, dynamic>?>(
            future: UserRepository().getUserById(resolvedSenderId),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final fetched = (data?['fullName'] as String?)?.trim() ??
                  (data?['fullname'] as String?)?.trim() ??
                  '';
              if (fetched.isEmpty || _isPlaceholderName(fetched)) {
                return const SizedBox.shrink();
              }
              return Text(fetched, style: style);
            },
          );
        },
      );
    }

    final resolvedFullName = fullName?.trim() ?? '';
    if (resolvedFullName.isNotEmpty && !_isPlaceholderName(resolvedFullName)) {
      return Text(resolvedFullName, style: style);
    }
    
    return const SizedBox.shrink();
  }

  bool _isPlaceholderName(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'unknown user' ||
        normalized == 'unkonwn user' ||
        normalized == 'unknow user' ||
        normalized == 'usuário' ||
        normalized == 'usuario';
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
    
    final rawUrlInMessage = _extractFirstUrl(displayMessage);
    final launchableUri = rawUrlInMessage != null ? _toLaunchableUri(rawUrlInMessage) : null;
    final hasLinkPreview = !isSystem && (imageUrl == null || imageUrl!.isEmpty) && launchableUri != null;

    final isLinkMessage = launchableUri != null;
    final messageStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: isSystem ? 13 : 16,
      fontWeight: isSystem
          ? FontWeight.w600
          : (isLinkMessage ? FontWeight.w700 : FontWeight.w400),
      letterSpacing: isSystem ? 0.2 : 0.0,
      color: isLinkMessage ? GlimpseColors.primaryDarker : textColor,
    );

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
                  onLongPress: isSystem
                      ? null
                      : () {
                          _showMessageActionsSheet(
                            context,
                            i18n: i18n,
                            messageText: displayMessage,
                            canReply: onLongPress != null,
                            onReply: onLongPress,
                            canDelete: onDelete != null,
                            onDelete: onDelete,
                          );
                        },
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
                              child: Builder(
                                builder: (context) {
                                  final key = stableImageCacheKey(imageUrl!);
                                  ImageCacheStats.instance.record(
                                    category: ImageCacheCategory.chatMedia,
                                    url: imageUrl!,
                                    cacheKey: key,
                                  );

                                  return CachedNetworkImage(
                                    imageUrl: imageUrl!,
                                    cacheManager: ChatMediaImageCache.instance,
                                    cacheKey: key,
                                width: 200,
                                height: 200,
                                fit: BoxFit.cover,
                                placeholder: (context, _) {
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
                                errorWidget: (context, _, __) {
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
                                          Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey[600],
                                            size: 40,
                                          ),
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
                                  );
                                },
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: (launchableUri != null) ? () => _openUrl(launchableUri) : null,
                              child: Text.rich(
                                TextSpan(
                                  children: _parseMarkdown(
                                    displayMessage,
                                    messageStyle,
                                  ),
                                ),
                                textAlign: isSystem ? TextAlign.center : TextAlign.left,
                              ),
                            ),
                            if (hasLinkPreview) _buildLinkPreviewCard(context, launchableUri),
                          ],
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

class _LinkPreviewData {
  const _LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  final Uri url;
  final String? title;
  final String? description;
  final String? imageUrl;
}
