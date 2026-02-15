import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
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
import 'package:partiu/shared/widgets/navigation_buttons.dart';

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
    
    // Conteúdo principal (compartilhado entre modo normal e sugestão)
    final content = _buildContent(context, screenHeight);
    
    // Se estiver em modo sugestão, usa Scaffold com AppBar para safe area
    if (_controller.isSuggestionMode) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: content,
      );
    }
    
    // Modo normal: bottom sheet padrão
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.r),
          topRight: Radius.circular(20.r),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: content,
      ),
    );
  }
  
  Widget _buildContent(BuildContext context, double screenHeight) {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: _controller.isSuggestionMode ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: EdgeInsets.only(
              top: 12.h,
              left: 20.w,
              right: 20.w,
            ),
            child: Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: GlimpseColors.borderColorLight,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
          ),

          SizedBox(height: 12.h),

          // Container com emoji
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                width: double.infinity,
                height: 120.h,
                color: _containerColor,
                    child: Stack(
                      children: [
                        // Imagem de fundo com scale maior
                        Positioned.fill(
                          child: Transform.scale(
                            scale: 1.5,
                            child: Image.asset(
                              'assets/images/carnaval.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Emoji centralizado
                        Center(
                          child: Text(
                            _controller.currentEmoji,
                            style: TextStyle(fontSize: 48.sp),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: 24.h),

              // Título
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context).translate('create_activity_title'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 20.sp,
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
                              size: 24.w,
                            )
                          : Text(
                              AppLocalizations.of(context).translate('see_suggestions'),
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: GlimpseColors.primary,
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),

              // Text Field (apenas visível se não estiver em modo sugestão)
              if (!_controller.isSuggestionMode)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
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
                          fontSize: 16.sp,
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
                                  size: 20.w,
                                ),
                              )
                            : null,
                        suffixIconConstraints: BoxConstraints(
                          minHeight: 40.h,
                          minWidth: 40.w,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                      ),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w400,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                  ),
                ),

              if (!_controller.isSuggestionMode)
                SizedBox(height: 8.h),

              // Área de sugestões expandível
              if (_controller.isSuggestionMode)
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 24.h,
                    ),
                    child: SuggestionTagsView(
                      onSuggestionSelected: _onSuggestionSelected,
                    ),
                  ),
                ),

              // Botões de voltar e continuar (apenas visível se não estiver em modo sugestão)
              if (!_controller.isSuggestionMode)
                NavigationButtons(
                  onBack: () => Navigator.of(context).pop(),
                  onContinue: _handleCreate,
                  canContinue: _controller.canContinue,
                ),

              // Padding bottom para safe area (apenas se não estiver em modo sugestão)
              if (!_controller.isSuggestionMode)
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16.h),
            ],
          ),
        );
  }
}
