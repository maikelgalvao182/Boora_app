import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Centralized styles for Conversations feature to avoid recreating TextStyles
/// and to eliminate hardcoded values across all conversation components
class ConversationStyles {
  ConversationStyles._();

  // ============================================================================
  // AVATAR & IMAGES
  // ============================================================================
  
  /// Tamanho padrão do avatar na lista de conversas (conversation_tile)
  static double get avatarSize => 52.w;
  
  /// Tamanho do avatar no app bar do chat (chat_app_bar_widget)
  static double get avatarSizeChatAppBar => 40.w;
  
  /// Border radius do avatar (quadrado com cantos arredondados)
  static BorderRadius get avatarRadius => BorderRadius.all(Radius.circular(8.r));
  
  /// Tamanho do ícone de verificação ao lado do nome
  static double get verifiedIconSize => 14.w;
  
  /// Espaçamento entre nome e ícone de verificação
  static double get verifiedIconSpacing => 4.w;

  // ============================================================================
  // EVENT EMOJI CONTAINER (usado em conversation_tile e chat_app_bar)
  // ============================================================================
  
  /// Border radius do container de emoji do evento
  static double get eventEmojiContainerRadius => 8.r;
  
  /// Cor de fundo do container de emoji do evento
  static Color eventEmojiContainerBg() => GlimpseColors.lightTextField;
  
  /// Tamanho da fonte do emoji no conversation_tile
  static double get eventEmojiFontSize => 24.sp;
  
  /// Tamanho da fonte do emoji no chat_app_bar_widget
  static double get eventEmojiFontSizeChatAppBar => 24.sp;
  
  /// Emoji padrão quando não especificado
  static const String eventEmojiDefault = '🎉';

  // ============================================================================
  // SPACING & PADDING
  // ============================================================================
  
  /// Espaçamento entre o botão de voltar e o avatar no chat_app_bar
  static double get chatAppBarBackButtonSpacing => 12.w;
  
  /// Espaçamento entre o avatar e o nome no chat_app_bar
  static double get chatAppBarAvatarNameSpacing => 12.w;
  
  /// Espaçamento entre nome e status (time-ago/schedule) no chat_app_bar
  static double get chatAppBarNameStatusSpacing => 4.h;
  
  /// Espaçamento entre time-ago e presença no chat_app_bar
  static double get chatAppBarTimePresenceSpacing => 8.w;
  
  /// Padding do trailing do chat_app_bar
  static double get chatAppBarTrailingPadding => 20.w;
  
  /// Espaçamento entre elementos no trailing (tempo e badge)
  static double get trailingChipSpacing => 6.w;
  
  /// Espaçamento entre o header e a lista
  static double get headerSpacing => 8.h;
  
  /// Padding do footer loader (carregando mais conversas)
  static EdgeInsets get footerLoaderPadding => EdgeInsets.symmetric(vertical: 16.h);
  
  /// Padding do header da tela de conversas
  static EdgeInsets get headerPadding => EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 0);
  
  /// Padding do chip "new" (não lida)
  static EdgeInsets get unreadChipPadding => EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h);
  
  /// Padding zero para remover espaçamentos indesejados
  static const EdgeInsets zeroPadding = EdgeInsets.zero;

  // ============================================================================
  // DIMENSIONS
  // ============================================================================
  
  /// Tamanho do loader (CupertinoActivityIndicator)
  static double get loaderSize => 24.w;
  
  /// Raio do footer loader
  static double get footerLoaderRadius => 14.r;
  
  /// Threshold para detectar quando está próximo do fim da lista
  static const int nearEndThreshold = 5;
  
  /// Altura do divider entre conversas
  static double get dividerHeight => 1.h;
  
  /// Tamanho do ícone de busca no header
  static double get searchIconSize => 22.w;

  // ============================================================================
  // BORDER RADIUS
  // ============================================================================
  
  /// Border radius do chip "new" (não lida)
  static BorderRadius get unreadChipRadius => BorderRadius.all(Radius.circular(10.r));

  // ============================================================================
  // TEXT STYLES - TYPOGRAPHY
  // ============================================================================
  
  /// Tamanho da fonte do título (nome do usuário)
  static double get titleFontSize => 16.sp;
  
  /// Peso da fonte do título
  static const FontWeight titleFontWeight = FontWeight.w600;
  
  /// Tamanho da fonte do activityText (nome do evento)
  static double get eventNameFontSize => 15.sp;
  
  /// Peso da fonte do activityText
  static const FontWeight eventNameFontWeight = FontWeight.w700;
  
  /// Tamanho da fonte do subtítulo (última mensagem)
  static double get subtitleFontSize => 13.sp;
  
  /// Tamanho da fonte do label de tempo
  static double get timeLabelFontSize => 12.sp;
  
  /// Peso da fonte do label de tempo
  static const FontWeight timeLabelFontWeight = FontWeight.w500;
  
  /// Tamanho da fonte do chip "new"
  static double get unreadChipFontSize => 12.sp;
  
  /// Peso da fonte do chip "new"
  static const FontWeight unreadChipFontWeight = FontWeight.w600;
  
  /// Line height para textos com markdown
  static const double markdownLineHeight = 1.4;
  
  /// Peso da fonte para texto bold no markdown
  static const FontWeight markdownBoldWeight = FontWeight.w700;

  // ============================================================================
  // TEXT STYLES - COMPOSED
  // ============================================================================
  
  /// Estilo do título (display name) - usado em conversation_tile e chat_app_bar
  static TextStyle title({Color? color}) => GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS, 
        fontSize: titleFontSize,
        fontWeight: titleFontWeight,
        color: color ?? GlimpseColors.textSubTitle,
      );

  /// Estilo do subtítulo (last message) - usado em conversation_tile e chat_app_bar
  static TextStyle subtitle({Color? color}) => GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: subtitleFontSize,
        color: color ?? GlimpseColors.textSubTitle,
      );

  /// Estilo do label de tempo (trailing time) - usado em conversation_tile
  static TextStyle timeLabel({Color? color}) => GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS, 
        fontSize: timeLabelFontSize,
        fontWeight: timeLabelFontWeight,
        color: color ?? GlimpseColors.textSubTitle,
      );

  /// Estilo do texto do chip "new" (unread badge)
  static TextStyle unreadChipText() => TextStyle(
        color: Colors.white,
        fontSize: unreadChipFontSize,
        fontWeight: unreadChipFontWeight,
      );
  
  /// Estilo do texto de emoji (eventos) - usado em conversation_tile e chat_app_bar
  static TextStyle eventEmojiText() => TextStyle(
        fontSize: eventEmojiFontSize,
      );
  
  /// Estilo do texto de emoji no chat app bar (eventos)
  static TextStyle eventEmojiTextChatAppBar() => TextStyle(
        fontSize: eventEmojiFontSizeChatAppBar,
      );

  // ============================================================================
  // COLORS - STATIC
  // ============================================================================
  
  /// Cor de fundo da tela
  static Color backgroundColor() => GlimpseColors.textSubTitle;

  /// Cor de fundo do chip "new" (não lida)
  static Color unreadChipBg() => GlimpseColors.primaryColorLight;

  /// Cor do divider entre conversas
  static Color dividerColor() => GlimpseColors.lightTextField;

  /// Cor do ícone de busca no header
  static Color searchIconColor() => GlimpseColors.textSubTitle;

  /// Cor do loader
  static Color loaderColor() => Colors.black54;
  
  /// Cor de fundo do tile quando há mensagem não lida
  static Color unreadTileBackground() => GlimpseColors.lightTextField;

  // ============================================================================
  // MARKDOWN STYLES
  // ============================================================================
  
  /// Spacing entre blocos de markdown
  static const double markdownBlockSpacing = 0;
  
  /// Indent de listas no markdown
  static const double markdownListIndent = 0;

  // ============================================================================
  // BOX CONSTRAINTS
  // ============================================================================
  
  /// Box constraints vazio para remover tamanho mínimo de botões
  static const BoxConstraints emptyConstraints = BoxConstraints();
  
  // ============================================================================
  // WIDGET BUILDERS - EMOJI CONTAINER
  // ============================================================================
  
  /// Constrói o container de emoji para eventos (conversation_tile)
  /// Garante consistência visual entre conversation_tile e chat_app_bar
  static Widget buildEventEmojiContainer({
    required String emoji,
    double? size,
  }) {
    return Container(
      width: size ?? avatarSize,
      height: size ?? avatarSize,
      decoration: BoxDecoration(
        color: eventEmojiContainerBg(),
        borderRadius: BorderRadius.circular(eventEmojiContainerRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        emoji.isNotEmpty ? emoji : eventEmojiDefault,
        style: eventEmojiText(),
      ),
    );
  }
  
  /// Constrói o container de emoji para eventos no chat app bar
  /// Mesmo estilo do conversation_tile, mas tamanho pode ser customizado
  static Widget buildEventEmojiContainerChatAppBar({
    required String emoji,
    double? size,
  }) {
    return Container(
      width: size ?? avatarSizeChatAppBar,
      height: size ?? avatarSizeChatAppBar,
      decoration: BoxDecoration(
        color: eventEmojiContainerBg(),
        borderRadius: BorderRadius.circular(eventEmojiContainerRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        emoji.isNotEmpty ? emoji : eventEmojiDefault,
        style: eventEmojiTextChatAppBar(),
      ),
    );
  }
  
  // ============================================================================
  // WIDGET BUILDERS - EVENT NAME TEXT
  // ============================================================================
  
  /// Constrói o Text do nome do evento (activityText)
  /// Garante consistência visual entre conversation_tile e chat_app_bar
  /// Usa fonte 14px e cor primaryColorLight conforme especificação
  static Widget buildEventNameText({
    required String name,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return Text(
      name,
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: eventNameFontSize,
        fontWeight: eventNameFontWeight,
        color: GlimpseColors.primaryColorLight,
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
