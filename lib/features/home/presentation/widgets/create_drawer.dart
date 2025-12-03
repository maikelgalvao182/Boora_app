import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/activity_helper.dart';
import 'package:partiu/core/utils/emoji_helper.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/home/presentation/widgets/create/suggestion_tags_view.dart';
import 'package:partiu/features/home/presentation/widgets/controllers/create_drawer_controller.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/plugins/locationpicker/entities/location_result.dart';
import 'package:partiu/shared/widgets/animated_emoji.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';

/// Bottom sheet para criar nova atividade
class CreateDrawer extends StatefulWidget {
  const CreateDrawer({super.key, this.coordinator});

  final CreateFlowCoordinator? coordinator;

  @override
  State<CreateDrawer> createState() => _CreateDrawerState();
}

class _CreateDrawerState extends State<CreateDrawer> {
  late final CreateDrawerController _controller;
  late final CreateFlowCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _controller = CreateDrawerController();
    _coordinator = widget.coordinator ?? CreateFlowCoordinator();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_controller.isUpdatingFromSuggestion) {
      final text = _controller.textController.text;
      final emoji = EmojiHelper.getEmojiForText(text);

      if (emoji != null) {
        _controller.setEmoji(emoji);
      } else if (text.isEmpty && _controller.currentEmoji != '🎉') {
        _controller.setEmoji('🎉');
      }
    }
  }

  void _toggleSuggestionMode() {
    _controller.toggleSuggestionMode();
    if (_controller.isSuggestionMode) {
      FocusScope.of(context).unfocus();
    }
    setState(() {}); // Forçar rebuild para atualizar UI
  }

  void _onSuggestionSelected(String text) {
    final emoji = ActivityHelper.getEmojiForActivity(text);
    _controller.setSuggestion(text, emoji);
    // O controller já define isSuggestionMode = false, apenas atualizamos a UI
    setState(() {});
  }

  void _handleCreate() async {
    if (!_controller.canContinue) return;

    // Salvar informações no coordinator
    _coordinator.setActivityInfo(
      _controller.textController.text,
      _controller.currentEmoji,
    );

    final navigator = Navigator.of(context);
    
    // Fechar teclado
    FocusScope.of(context).unfocus();
    
    // Fechar o drawer imediatamente
    navigator.pop();

    // Navegar para o LocationPicker passando o coordinator
    try {
      final result = await navigator.push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => LocationPickerPageRefactored(
            coordinator: _coordinator,
          ),
          fullscreenDialog: true,
        ),
      );

      if (result != null) {
        debugPrint(_coordinator.summary);
      }
    } catch (e) {
      debugPrint('Erro na navegação: $e');
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
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
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
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: GlimpseColors.lightTextField,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Center(
                  child: AnimatedEmoji(
                    emoji: _controller.currentEmoji,
                    size: 40,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Título
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'E aí, Partiu?',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.textSubTitle,
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
                              'Ver sugestões',
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

              // Text Field
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
                    onTap: () {
                      if (_controller.isSuggestionMode) {
                        _controller.toggleSuggestionMode();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Correr no parque, tomar um chop...',
                      hintStyle: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.textHint,
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
                    text: 'Continuar',
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
