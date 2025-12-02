import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Estilos de texto centralizados para o aplicativo
/// Define estilos padronizados para títulos, subtítulos e textos em geral
class TextStyles {
  // Private constructor to prevent instantiation
  TextStyles._();

  // TÍTULOS DE TELA (Headers principais)
  
  /// Título principal das telas de cadastro e outras páginas importantes
  /// Usado em headers de telas como "Create Account", "Sign In", etc.
  static TextStyle get screenTitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Colors.black,
    height: 1.2,
  );

  /// Título dos cabeçalhos das telas (GlimpseProgressHeader)
  /// Usado para títulos principais como "Create Account", "Sign In", etc.
  static TextStyle get headerTitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: GlimpseColors.textSubTitle,
  );

  /// Subtítulo dos cabeçalhos das telas (GlimpseProgressHeader)
  /// Usado para instruções como "enter_your_credentials_to_continue", etc.
  static TextStyle get headerSubtitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: GlimpseColors.textSubTitle,
  );

  /// Título para telas de avaliação e feedback
  /// Usado em telas como tela_avaliacao_vendor para títulos destacados
  static TextStyle get evaluationTitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Colors.black,
    height: 1.2,
  );

  /// Título de sucesso (usado em tela_sucesso_cadastro)
  static TextStyle get successTitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  /// Título de rating/avaliação com número destacado
  static TextStyle get ratingTitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  /// Título de depoimento/testimonial
  static TextStyle get testimonialName => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  // SUBTÍTULOS E DESCRIÇÕES

  /// Subtítulo principal das telas (descrição abaixo do título)
  /// Usado para explicar o que o usuário deve fazer na tela
  static TextStyle get screenSubtitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: GlimpseColors.textSubTitle,
    height: 1.4,
  );

  /// Subtítulo de descrição mais sutil
  /// Usado para informações complementares e instruções
  static TextStyle get description => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: GlimpseColors.textSubTitle,
    height: 1.4,
  );

  /// Subtítulo de sucesso (mensagem abaixo do título de sucesso)
  static TextStyle get successSubtitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.black.withValues(alpha: 0.75),
  );

  /// Descrição de reviews/avaliações
  static TextStyle get reviewsDescription => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Colors.black.withValues(alpha: 0.55),
  );

  /// Categoria em depoimentos (texto secundário após nome)
  static TextStyle get testimonialCategory => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.black.withValues(alpha: 0.6),
  );

  /// Texto de depoimento/testimonial
  static TextStyle get testimonialText => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: Colors.black.withValues(alpha: 0.75),
  );

  /// Descrição destacada para onboarding e avatares
  static TextStyle get highlightDescription => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black.withValues(alpha: 0.55),
  );

  // TEXTOS DE NAVEGAÇÃO E LINKS

  /// Texto de link para navegação (ex: "Don't have account?")
  static TextStyle get navigationText => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    color: GlimpseColors.textSubTitle,
    fontSize: 14,
  );

  /// Link clicável de navegação (ex: "Sign Up", "Back to Sign In")
  static TextStyle get navigationLink => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    color: GlimpseColors.primaryColorLight,
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  /// Link de "Forgot Password" e similares
  static TextStyle get actionLink => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    color: GlimpseColors.primaryColorLight,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  // TEXTOS DE FORM E INPUT

  /// Label de campos de formulário
  static TextStyle get inputLabel => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    color: GlimpseColors.textSubTitle,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  // TEXTOS DE AUTENTICAÇÃO

  /// Título principal das telas de autenticação (branco sobre fundo escuro)
  /// Usado em telas como sign_in_screen para o título principal
  static TextStyle get authTitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );

  /// Subtítulo das telas de autenticação (branco translúcido sobre fundo escuro)
  /// Usado para descrições e instruções em telas de auth
  static TextStyle get authSubtitle => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: Colors.white.withValues(alpha: 0.90),
  );

  // TEXTOS GERAIS

  /// Texto padrão para conteúdo geral
  static TextStyle get bodyText => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.black.withValues(alpha: 0.8),
    height: 1.4,
  );

  /// Texto pequeno para informações secundárias
  static TextStyle get caption => GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.black.withValues(alpha: 0.6),
  );

  // MÉTODOS UTILITÁRIOS

  /// Retorna uma variação do estilo de título com cor personalizada
  static TextStyle screenTitleWithColor(Color color) => screenTitle.copyWith(color: color);

  /// Retorna uma variação do estilo de subtítulo com cor personalizada  
  static TextStyle screenSubtitleWithColor(Color color) => screenSubtitle.copyWith(color: color);

  /// Retorna uma variação do estilo de descrição com cor personalizada
  static TextStyle descriptionWithColor(Color color) => description.copyWith(color: color);

  /// Retorna uma variação do texto de navegação com cor personalizada
  static TextStyle navigationTextWithColor(Color color) => navigationText.copyWith(color: color);
}
