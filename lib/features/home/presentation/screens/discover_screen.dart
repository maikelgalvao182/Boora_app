import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/widgets/google_map_view.dart';
import 'package:partiu/features/home/presentation/viewmodels/apple_map_viewmodel.dart';

/// Tela de descoberta de atividades com mapa interativo
/// 
/// Esta tela exibe um mapa Google Maps com a localização do usuário.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key, 
    this.onCenterUserRequested,
    required this.mapViewModel,
  });

  final VoidCallback? onCenterUserRequested;
  final AppleMapViewModel mapViewModel;

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

class DiscoverScreenState extends State<DiscoverScreen> {
  final GlobalKey<GoogleMapViewState> _mapKey = GlobalKey<GoogleMapViewState>();

  @override
  void initState() {
    super.initState();
    // Notifica o callback quando o widget é criado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCenterUserRequested?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: GoogleMapView(
        key: _mapKey,
        viewModel: widget.mapViewModel,
      ),
    );
  }

  /// Centraliza o mapa na localização do usuário
  void centerOnUser() {
    _mapKey.currentState?.centerOnUser();
  }
}
