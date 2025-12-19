import 'package:flutter/material.dart';

/// Pin personalizado fixo no centro do mapa
class MapCenterPin extends StatelessWidget {
  const MapCenterPin({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/pim.png',
      width: 48,
      height: 48,
      fit: BoxFit.contain,
    );
  }
}
