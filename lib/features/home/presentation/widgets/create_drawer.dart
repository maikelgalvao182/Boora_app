import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/emoji_helper.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/features/home/presentation/widgets/create/suggestion_tags_view.dart';
import 'package:partiu/features/home/presentation/widgets/controllers/create_drawer_controller.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/shared/widgets/emoji_container.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';

/// Bottom sheet para criar nova atividade
class CreateDrawer extends StatefulWidget {
  const CreateDrawer({
    super.key, 
    required this.coordinator,
    this.initialName,
    this.initialEmoji,
    this.editMode = false,
  });

  final CreateFlowCoordinator coordinator;
  final String? initialName;
  final String? initialEmoji;
  final bool editMode;

  @override
  State<CreateDrawer> createState() => _CreateDrawerState();
}

class _CreateDrawerState extends State<CreateDrawer> {
  late final CreateDrawerController _controller;
  late final CreateFlowCoordinator _coordinator;
  late final Color _containerColor;

  @override
  void initState() {
    super.initState();
    _controller = CreateDrawerController();
    _coordinator = widget.coordinator;
    _controller.addListener(_onControllerChanged);
    
    // Gera uma cor aleatória ao abrir o drawer
    _containerColor = MarkerColorHelper.getRandomColor();
    
    // Preencher com valores do coordinator (se existirem) ou valores iniciais
    final savedName = widget.initialName ?? _coordinator.draft.activityText;
    final savedEmoji = widget.initialEmoji ?? _coordinator.draft.emoji;
    
    if (savedName != null && savedName.isNotEmpty) {
      _controller.textController.text = savedName;
    }
    if (savedEmoji != null && savedEmoji.isNotEmpty) {
      _controller.setEmoji(savedEmoji);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Ignorar se estiver atualizando de sugestão
    if (_controller.isUpdatingFromSuggestion) {
      return;
    }
    
    // Se o emoji está bloqueado para o texto atual, não alterar
    if (_controller.isEmojiLockedForCurrentText()) {
      return;
    }
    
    final text = _controller.textController.text;
    final emoji = EmojiHelper.getEmojiForText(text);

    if (emoji != null) {
      _controller.setEmoji(emoji);
    } else if (text.isEmpty && _controller.currentEmoji != '🎉') {
      _controller.setEmoji('🎉');
    }

    // Rebuild imediato para refletir:
    // - enable/disable do botão (canContinue)
    // - exibição do ícone X (limpar)
    // - emoji atualizado
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleSuggestionMode() {
    _controller.toggleSuggestionMode();
    if (_controller.isSuggestionMode) {
      FocusScope.of(context).unfocus();
    }
    setState(() {}); // Forçar rebuild para atualizar UI
  }

  void _onSuggestionSelected(ActivitySuggestion suggestion) {
    final i18n = AppLocalizations.of(context);
    final text = i18n.translate(suggestion.textKey);
    _controller.setSuggestion(text, suggestion.emoji);
    // O controller já define isSuggestionMode = false, apenas atualizamos a UI
    setState(() {});
  }

  void _handleCreate() async {
    if (!_controller.canContinue) return;

    // Se estiver em modo de edição, apenas retornar os valores
    if (widget.editMode) {
      Navigator.of(context).pop({
        'name': _controller.textController.text.trim(),
        'emoji': _controller.currentEmoji,
      });
      return;
    }

    // Salvar informações no coordinator
    _coordinator.setActivityInfo(
      _controller.textController.text,
      _controller.currentEmoji,
    );

    // Fechar teclado
    FocusScope.of(context).unfocus();
    
    // Fechar o CreateDrawer e retornar indicação para abrir CategoryDrawer
    if (mounted) {
      Navigator.of(context).pop({'action': 'openCategory'});
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _controller.isSuggestionMode ? screenHeight : null,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _controller.isSuggestionMode 
            ? BorderRadius.zero 
            : const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: _controller.isSuggestionMode ? 0 : MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle e botão de fechar
              Padding(
                padding: EdgeInsets.only(
                  top: _controller.isSuggestionMode ? MediaQuery.of(context).padding.top + 12 : 12,
                  left: 20,
                  right: 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Handle centralizado (spacer para ocupar espaço)
                    const SizedBox(width: 32),
                    
                    // Handle no centro
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: GlimpseColors.borderColorLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    
                    // Botão de fechar
                    const GlimpseCloseButton(
                      size: 32,
                    ),
                  ],
                ),
              ),

              // Container com emoji
              EmojiContainer(
                emoji: _controller.currentEmoji,
                size: 80,
                emojiSize: 40,
                backgroundColor: _containerColor,
              ),

              const SizedBox(height: 24),

              // Título
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context).translate('create_activity_title'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleSuggestionMode,
                      child: _controller.isSuggestionMode
                          ? Icon(
                              Icons.close,
                              color: GlimpseColors.primary,
                              size: 24,
                            )
                          : Text(
                              AppLocalizations.of(context).translate('see_suggestions'),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: GlimpseColors.primary,
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Text Field (apenas visível se não estiver em modo sugestão)
              if (!_controller.isSuggestionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _controller.textController,
                      autofocus: !_controller.isSuggestionMode,
                      maxLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (text) {
                        // Desbloquear emoji quando usuário editar manualmente
                        // (só desbloqueia se o texto mudou em relação à sugestão)
                        if (!_controller.isUpdatingFromSuggestion) {
                          _controller.unlockEmoji();
                        }
                      },
                      onTap: () {
                        if (_controller.isSuggestionMode) {
                          _controller.toggleSuggestionMode();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).translate('activity_placeholder'),
                        hintStyle: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textHint,
                        ),
                        suffixIcon: _controller.textController.text.trim().isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _controller.clear();
                                },
                                icon: Icon(
                                  Icons.close,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              )
                            : null,
                        suffixIconConstraints: const BoxConstraints(
                          minHeight: 40,
                          minWidth: 40,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                  ),
                ),

              if (!_controller.isSuggestionMode)
                const SizedBox(height: 8),

              // Área de sugestões expandível
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _controller.isSuggestionMode 
                    ? (screenHeight - MediaQuery.of(context).padding.top - 280) 
                    : 0,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: SuggestionTagsView(
                    onSuggestionSelected: _onSuggestionSelected,
                  ),
                ),
              ),

              // Botão de criar (apenas visível se não estiver em modo sugestão)
              if (!_controller.isSuggestionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GlimpseButton(
                    text: widget.editMode 
                        ? AppLocalizations.of(context).translate('save')
                        : AppLocalizations.of(context).translate('continue'),
                    onPressed: _controller.canContinue
                        ? _handleCreate
                        : null,
                  ),
                ),

              // Padding bottom para safe area (apenas se não estiver em modo sugestão)
              if (!_controller.isSuggestionMode)
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}
