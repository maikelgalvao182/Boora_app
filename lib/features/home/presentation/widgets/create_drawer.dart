import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/presentation/screens/location_picker_page.dart';
import 'package:partiu/plugins/locationpicker/entities/location_result.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';

/// Bottom sheet para criar nova atividade
class CreateDrawer extends StatefulWidget {
  const CreateDrawer({super.key});

  @override
  State<CreateDrawer> createState() => _CreateDrawerState();
}

class _CreateDrawerState extends State<CreateDrawer> {
  final TextEditingController _activityController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _activityController.dispose();
    super.dispose();
  }

  void _handleCreate() async {
    if (_activityController.text.trim().isEmpty) {
      // TODO: Mostrar erro - campo vazio
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Fechar o bottom sheet atual antes de navegar
      Navigator.of(context).pop();

      // Abrir seletor de localização em tela cheia
      final LocationResult? locationResult = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const LocationPickerPage(),
        ),
      );

      // Se o usuário selecionou uma localização
      if (locationResult != null && locationResult.latLng != null) {
        // TODO: Continuar com a criação da atividade
        // Dados disponíveis:
        // - _activityController.text (título da atividade)
        // - locationResult.latLng (coordenadas)
        // - locationResult.formattedAddress (endereço completo)
        // - locationResult.name (nome do local)
        debugPrint('Atividade: ${_activityController.text}');
        debugPrint('Local: ${locationResult.formattedAddress}');
        debugPrint('Coordenadas: ${locationResult.latLng}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle e botão de fechar
              Padding(
                padding: const EdgeInsets.only(
                  top: 12,
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
                child: const Center(
                  child: Text(
                    '🎉',
                    style: TextStyle(fontSize: 40),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Título
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Partiu...',
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: GlimpseColors.textSubTitle,
                    ),
                  ),
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
                    controller: _activityController,
                    autofocus: true,
                    maxLines: 1,
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

              // Botão de criar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GlimpseButton(
                  text: 'Continuar',
                  onPressed: _isProcessing ? null : _handleCreate,
                  isProcessing: _isProcessing,
                ),
              ),

              // Padding bottom para safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}
