import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Centralized styles for Conversations feature to avoid recreating TextStyles
/// and to eliminate hardcoded values across all conversation components
class ConversationStyles {
  ConversationStyles._();

  // ============================================================================
  // AVATAR & IMAGES
  // ============================================================================
  
  /// Tamanho padrão do avatar na lista de conversas
  static const double avatarSize = 40;
  
  /// Border radius do avatar (quadrado com cantos arredondados)
  static const BorderRadius avatarRadius = BorderRadius.all(Radius.circular(8));
  
  /// Tamanho do ícone de verificação ao lado do nome
  static const double verifiedIconSize = 14;
  
  /// Espaçamento entre nome e ícone de verificação
  static const double verifiedIconSpacing = 4;

  // ============================================================================
  // SPACING & PADDING
  // ============================================================================
  
  /// Espaçamento entre elementos no trailing (tempo e badge)
  static const double trailingChipSpacing = 6;
  
  /// Espaçamento entre o header e a lista
  static const double headerSpacing = 8;
  
  /// Padding do footer loader (carregando mais conversas)
  static const EdgeInsets footerLoaderPadding = EdgeInsets.symmetric(vertical: 16);
  
  /// Padding do header da tela de conversas
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(20, 8, 20, 0);
  
  /// Padding do chip "new" (não lida)
  static const EdgeInsets unreadChipPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  
  /// Padding zero para remover espaçamentos indesejados
  static const EdgeInsets zeroPadding = EdgeInsets.zero;

  // ============================================================================
  // DIMENSIONS
  // ============================================================================
  
  /// Tamanho do loader (CupertinoActivityIndicator)
  static const double loaderSize = 24;
  
  /// Raio do footer loader
  static const double footerLoaderRadius = 14;
  
  /// Threshold para detectar quando está próximo do fim da lista
  static const int nearEndThreshold = 5;
  
  /// Altura do divider entre conversas
  static const double dividerHeight = 1;
  
  /// Tamanho do ícone de busca no header
  static const double searchIconSize = 22;

  // ============================================================================
  // BORDER RADIUS
  // ============================================================================
  
  /// Border radius do chip "new" (não lida)
  static const BorderRadius unreadChipRadius = BorderRadius.all(Radius.circular(10));

  // ============================================================================
  // TEXT STYLES - TYPOGRAPHY
  // ============================================================================
  
  /// Tamanho da fonte do título (nome do usuário)
  static const double titleFontSize = 16;
  
  /// Peso da fonte do título
  static const FontWeight titleFontWeight = FontWeight.w600;
  
  /// Tamanho da fonte do subtítulo (última mensagem)
  static const double subtitleFontSize = 13;
  
  /// Tamanho da fonte do label de tempo
  static const double timeLabelFontSize = 12;
  
  /// Peso da fonte do label de tempo
  static const FontWeight timeLabelFontWeight = FontWeight.w500;
  
  /// Tamanho da fonte do chip "new"
  static const double unreadChipFontSize = 12;
  
  /// Peso da fonte do chip "new"
  static const FontWeight unreadChipFontWeight = FontWeight.w600;
  
  /// Line height para textos com markdown
  static const double markdownLineHeight = 1.4;
  
  /// Peso da fonte para texto bold no markdown
  static const FontWeight markdownBoldWeight = FontWeight.w700;

  // ============================================================================
  // TEXT STYLES - COMPOSED
  // ============================================================================
  
  /// Estilo do título (display name)
  static TextStyle title() => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: titleFontSize,
        fontWeight: titleFontWeight,
        color: GlimpseColors.textSubTitle,
      );

  /// Estilo do subtítulo (last message)
  static TextStyle subtitle() => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: subtitleFontSize,
        color: GlimpseColors.textSubTitle,
      );

  /// Estilo do label de tempo (trailing time)
  static TextStyle timeLabel() => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: timeLabelFontSize,
        fontWeight: timeLabelFontWeight,
        color: GlimpseColors.textSubTitle,
      );

  /// Estilo do texto do chip "new" (unread badge)
  static const TextStyle unreadChipText = TextStyle(
    color: Colors.white,
    fontSize: unreadChipFontSize,
    fontWeight: unreadChipFontWeight,
  );

  // ============================================================================
  // COLORS - STATIC
  // ============================================================================
  
  /// Cor de fundo da tela
  static Color backgroundColor() => GlimpseColors.textSubTitle;

  /// Cor de fundo do chip "new" (não lida)
  static Color unreadChipBg() => GlimpseColors.primaryColorLight;

  /// Cor do divider entre conversas
  static Color dividerColor() => GlimpseColors.borderColorLight;

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
}
