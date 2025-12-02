import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Classe utilitária com estilos padronizados para diálogos
/// Usado por ReportDialog, DeleteAccountConfirmDialog e outros
class DialogStyles {
  DialogStyles._(); // Private constructor para prevenir instanciação

  // ==================== CONTAINER STYLES ====================
  
  /// Margem padrão do container principal do diálogo
  static const EdgeInsets containerMargin = EdgeInsets.symmetric(
    horizontal: 12,
  );
  
  /// Padding padrão do container principal do diálogo
  static const EdgeInsets containerPadding = EdgeInsets.fromLTRB(
    20,
    16,
    20,
    20,
  );
  
  /// Border radius padrão do container principal do diálogo
  static const BorderRadius containerBorderRadius = BorderRadius.all(
    Radius.circular(18),
  );
  
  /// Decoração padrão do container principal do diálogo
  static BoxDecoration get containerDecoration => const BoxDecoration(
    color: Colors.white,
    borderRadius: containerBorderRadius,
  );

  // ==================== CLOSE BUTTON STYLES ====================
  
  /// Tamanho do botão de fechar
  static const double closeButtonSize = 32;
  
  /// Border radius do botão de fechar
  static BorderRadius get closeButtonBorderRadius => BorderRadius.circular(8);
  
  /// Cor de fundo do botão de fechar
  static Color get closeButtonBackgroundColor => GlimpseColors.lightTextField;
  
  /// Ícone do botão de fechar
  static const IconData closeButtonIcon = Icons.close;
  
  /// Tamanho do ícone do botão de fechar
  static const double closeButtonIconSize = 24;
  
  /// Cor do ícone do botão de fechar
  static const Color closeButtonIconColor = Colors.black87;
  
  /// Splash radius do botão de fechar
  static const double closeButtonSplashRadius = 18;

  // ==================== ICON CONTAINER STYLES ====================
  
  /// Tamanho do container do ícone principal
  static const double iconContainerSize = 84;
  
  /// Border radius do container do ícone
  static BorderRadius get iconContainerBorderRadius => BorderRadius.circular(8);
  
  /// Cor de fundo do container do ícone
  static const Color iconContainerBackgroundColor = Colors.white;

  // ==================== TEXT STYLES ====================
  
  /// Estilo do título do diálogo
  static TextStyle get titleStyle => GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS, 
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: GlimpseColors.textSubTitle,
    letterSpacing: .3,
  );
  /// Estilo da mensagem/descrição do diálogo
  static TextStyle get messageStyle => GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS, 
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: GlimpseColors.textSubTitle,
  );
  
  /// Padding horizontal do texto da mensagem
  static const EdgeInsets messagePadding = EdgeInsets.symmetric(horizontal: 4);

  // ==================== BUTTON STYLES ====================
  
  /// Padding vertical dos botões
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(vertical: 14);
  
  /// Border radius dos botões
  static BorderRadius get buttonBorderRadius => BorderRadius.circular(12);
  
  /// Espaçamento entre os botões
  static const double buttonSpacing = 12;
  /// Estilo do texto dos botões
  static TextStyle get buttonTextStyle => GoogleFonts.getFont(
    FONT_PLUS_JAKARTA_SANS, 
    fontSize: 14,
    fontWeight: FontWeight.w800,
  );

  // ==================== NEGATIVE BUTTON (Outlined) ====================
  
  /// Cor da borda do botão negativo
  static Color get negativeButtonBorderColor => GlimpseColors.borderColorLight;
  
  /// Cor de fundo do botão negativo
  static const Color negativeButtonBackgroundColor = Colors.white;
  
  /// Cor do texto do botão negativo
  static const Color negativeButtonTextColor = Colors.black;
  
  /// Estilo completo do botão negativo (Outlined)
  static ButtonStyle get negativeButtonStyle => OutlinedButton.styleFrom(
    side: BorderSide(color: negativeButtonBorderColor),
    shape: RoundedRectangleBorder(borderRadius: buttonBorderRadius),
    padding: buttonPadding,
    backgroundColor: negativeButtonBackgroundColor,
  );
  
  /// Estilo do texto do botão negativo
  static TextStyle get negativeButtonTextStyle => buttonTextStyle.copyWith(
    color: negativeButtonTextColor,
  );

  // ==================== POSITIVE BUTTON (Elevated) ====================
  
  /// Cor de fundo do botão positivo (destrutivo/vermelho)
  static const Color positiveButtonBackgroundColor = Colors.red;
  
  /// Cor do texto do botão positivo
  static const Color positiveButtonTextColor = Colors.white;
  
  /// Elevação do botão positivo
  static const double positiveButtonElevation = 0;
  
  /// Estilo completo do botão positivo (Elevated)
  static ButtonStyle get positiveButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: positiveButtonBackgroundColor,
    foregroundColor: positiveButtonTextColor,
    shape: RoundedRectangleBorder(borderRadius: buttonBorderRadius),
    padding: buttonPadding,
    elevation: positiveButtonElevation,
  );
  
  /// Estilo do texto do botão positivo
  static TextStyle get positiveButtonTextStyle => buttonTextStyle.copyWith(
    color: positiveButtonTextColor,
  );

  // ==================== SUCCESS BUTTON (Elevated/Verde) ====================
  
  /// Cor de fundo do botão de sucesso (verde)
  static const Color successButtonBackgroundColor = Color(0xFF4CAF50);
  
  /// Cor do texto do botão de sucesso
  static const Color successButtonTextColor = Colors.white;
  
  /// Elevação do botão de sucesso
  static const double successButtonElevation = 0;
  
  /// Estilo completo do botão de sucesso (Elevated)
  static ButtonStyle get successButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: successButtonBackgroundColor,
    foregroundColor: successButtonTextColor,
    shape: RoundedRectangleBorder(borderRadius: buttonBorderRadius),
    padding: buttonPadding,
    elevation: successButtonElevation,
  );
  
  /// Estilo do texto do botão de sucesso
  static TextStyle get successButtonTextStyle => buttonTextStyle.copyWith(
    color: successButtonTextColor,
  );

  // ==================== SPACING VALUES ====================
  
  /// Espaçamento após o botão de fechar
  static const double spacingAfterCloseButton = 4;
  
  /// Espaçamento após o ícone
  static const double spacingAfterIcon = 14;
  
  /// Espaçamento após o título
  static const double spacingAfterTitle = 8;
  
  /// Espaçamento antes dos botões
  static const double spacingBeforeButtons = 20;
  
  /// Espaçamento final (após os botões)
  static const double spacingAfterButtons = 8;

  // ==================== HELPER WIDGETS ====================
  
  /// Widget do botão de fechar padrão
  static Widget buildCloseButton({required VoidCallback onPressed}) {
    return Container(
      height: closeButtonSize,
      width: closeButtonSize,
      decoration: BoxDecoration(
        color: closeButtonBackgroundColor,
        borderRadius: closeButtonBorderRadius,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(
          closeButtonIcon,
          size: closeButtonIconSize,
          color: closeButtonIconColor,
        ),
        splashRadius: closeButtonSplashRadius,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
  
  /// Widget do container do ícone principal
  static Widget buildIconContainer({required Widget icon}) {
    return Container(
      height: iconContainerSize,
      width: iconContainerSize,
      decoration: BoxDecoration(
        borderRadius: iconContainerBorderRadius,
        color: iconContainerBackgroundColor,
      ),
      child: Center(
        child: icon,
      ),
    );
  }
  
  /// Widget de ícone de aviso/warning com container vermelho suave
  static Widget buildWarningIcon({
    required IconData icon,
    double iconSize = 32,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.red,
        size: iconSize,
      ),
    );
  }
  
  /// Widget de ícone de pass/skip com container vermelho suave (consistente com PassButton)
  static Widget buildPassIcon({
    required IconData icon,
    double iconSize = 32,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE), // Mesma cor do PassButton
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.red,
        size: iconSize,
      ),
    );
  }
  
  /// Widget de ícone destrutivo/delete com container vermelho suave
  static Widget buildDeleteIcon({
    required IconData icon,
    double iconSize = 32,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.red,
        size: iconSize,
      ),
    );
  }
  
  /// Widget de ícone de sucesso com container verde suave
  static Widget buildSuccessIcon({
    required IconData icon,
    double iconSize = 32,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.green,
        size: iconSize,
      ),
    );
  }
  
  /// Widget de ícone de informação com container azul suave
  static Widget buildInfoIcon({
    required IconData icon,
    double iconSize = 32,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.blue,
        size: iconSize,
      ),
    );
  }
  
  /// Widget de ícone de alerta com container laranja suave
  static Widget buildAlertIcon({
    required IconData icon,
    double iconSize = 32,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.orange,
        size: iconSize,
      ),
    );
  }
  
  /// Widget do título do diálogo
  static Widget buildTitle(String title) {
    return Text(
      title,
      textAlign: TextAlign.center,
      style: titleStyle,
    );
  }
  
  /// Widget da mensagem do diálogo
  static Widget buildMessage(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: messagePadding,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: messageStyle,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
  
  /// Widget do botão negativo (Outlined)
  static Widget buildNegativeButton({
    required String text,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return Expanded(
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: negativeButtonStyle,
        child: Text(
          text,
          style: negativeButtonTextStyle,
        ),
      ),
    );
  }
  
  /// Widget do botão positivo (Elevated/Vermelho)
  static Widget buildPositiveButton({
    required String text,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return Expanded(
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: positiveButtonStyle,
        child: Text(
          text,
          style: positiveButtonTextStyle,
        ),
      ),
    );
  }
  
  /// Widget do botão informativo (Elevated/Azul)
  static Widget buildInfoButton({
    required String text,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return Expanded(
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: buttonBorderRadius,
          ),
          padding: buttonPadding,
          elevation: positiveButtonElevation,
        ),
        child: Text(
          text,
          style: positiveButtonTextStyle,
        ),
      ),
    );
  }
  
  /// Widget do botão de sucesso (Elevated/Verde)
  static Widget buildSuccessButton({
    required String text,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return Expanded(
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: successButtonStyle,
        child: Text(
          text,
          style: successButtonTextStyle,
        ),
      ),
    );
  }
  
  /// Widget da linha de botões (negativo + positivo)
  static Widget buildButtonRow({
    required String negativeText,
    required VoidCallback negativeAction,
    required String positiveText,
    required VoidCallback positiveAction,
    bool negativeEnabled = true,
    bool positiveEnabled = true,
  }) {
    return Row(
      children: [
        buildNegativeButton(
          text: negativeText,
          onPressed: negativeAction,
          enabled: negativeEnabled,
        ),
        const SizedBox(width: buttonSpacing),
        buildPositiveButton(
          text: positiveText,
          onPressed: positiveAction,
          enabled: positiveEnabled,
        ),
      ],
    );
  }
}
