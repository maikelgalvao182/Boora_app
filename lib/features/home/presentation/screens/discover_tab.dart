import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/screens/discover_screen.dart';
import 'package:partiu/features/home/presentation/widgets/create_button.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';

/// Tela de descoberta (Tab 0)
/// Exibe mapa interativo com atividades próximas
class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  void _showCreateDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mapa Apple Maps
        const DiscoverScreen(),
        
        // Botão flutuante no canto inferior direito
        Positioned(
          right: 16,
          bottom: 24,
          child: CreateButton(
            onPressed: () => _showCreateDrawer(context),
          ),
        ),
      ],
    );
  }
}
