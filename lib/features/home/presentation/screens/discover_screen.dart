import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/widgets/google_map_view.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

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
  final MapViewModel mapViewModel;

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

class DiscoverScreenState extends State<DiscoverScreen> {
  final GlobalKey<GoogleMapViewState> _mapKey = GlobalKey<GoogleMapViewState>();
  bool _platformMapCreated = false;
  bool _didScheduleClusterPreload = false;
  bool _firstRenderApplied = false;

  VoidCallback? _mapVmListener;

  @override
  void initState() {
    super.initState();
    // Notifica o callback quando o widget é criado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCenterUserRequested?.call();

      // 🚀 Lazy init do mapa: não travar Splash/Home.
      // A inicialização é idempotente no VM; aqui só disparamos de forma best-effort.
      unawaited(() async {
        try {
          await widget.mapViewModel.initialize();
        } catch (_) {
          // Inicialização do mapa não é crítica para navegação.
        }
      }());

      // Post-first-frame preload (prioridade baixa): aquece clusters sem travar UI.
      // Importante: no primeiro boot, o dataset inicial (MapDiscoveryService) pode levar
      // alguns segundos. Se fizermos zoom-out antes do dataset/map estarem prontos,
      // não aquece nada relevante.
      _scheduleClusterPreloadWhenReady();
    });
  }

  void _scheduleClusterPreloadWhenReady() {
    if (_didScheduleClusterPreload) return;

    VoidCallback? listener;
    listener = () {
      if (!mounted) return;

      // Só roda quando:
      // - o PlatformView do mapa já foi criado (evita animateCamera falhar)
      // - já temos dataset inicial (mapReady)
  // - o 1º render de markers já foi aplicado (evita aquecer clusters com dataset parcial)
  if (!_platformMapCreated || !widget.mapViewModel.mapReady || !_firstRenderApplied) return;

      widget.mapViewModel.removeListener(listener!);
      _mapVmListener = null;
      _didScheduleClusterPreload = true;

      // Prioridade baixa: deixa a UI respirar e não compete com o 1º onCameraIdle.
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
  // 1) Warmup de cobertura (dados): prefetch por viewport real com bounds expandido.
  unawaited(_mapKey.currentState?.prefetchExpandedBounds(bufferFactor: 2.5));

  // 2) Warmup de compute/UI: clusters/bitmaps em zoom baixo sem mexer na câmera.
  unawaited(_mapKey.currentState?.preloadZoomOutClusters(targetZoom: 3.0));
  
  // 3) Warmup de avatares de participantes: pré-carregar avatares dos participantes
  //    dos eventos visíveis para exibição instantânea no EventCard/ListCard.
  //    Disparado imediatamente (sem delay adicional) pois é prioridade alta para UX.
  unawaited(_mapKey.currentState?.warmupParticipantAvatars(
    maxEvents: 15,
    participantsPerEvent: 5,
  ));
      });
    };

    _mapVmListener = listener;
    widget.mapViewModel.addListener(listener);

    // Caso já esteja pronto quando chamarmos.
    listener();
  }

  @override
  void dispose() {
    final listener = _mapVmListener;
    if (listener != null) {
      widget.mapViewModel.removeListener(listener);
      _mapVmListener = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColoredBox(
          color: Colors.white,
          child: GoogleMapView(
            key: _mapKey,
            viewModel: widget.mapViewModel,
            onPlatformMapCreated: () {
              if (!mounted || _platformMapCreated) return;
              setState(() {
                _platformMapCreated = true;
              });

              // Se já está mapReady, podemos agendar o preload agora.
              _scheduleClusterPreloadWhenReady();
            },
            onFirstRenderApplied: () {
              if (!mounted || _firstRenderApplied) return;
              _firstRenderApplied = true;
              _scheduleClusterPreloadWhenReady();
            },
          ),
        ),

        // Spinner quando mapa ainda não foi criado
        if (!_platformMapCreated)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: CupertinoActivityIndicator(
                  color: GlimpseColors.textSubTitle,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Centraliza o mapa na localização do usuário
  void centerOnUser() {
    _mapKey.currentState?.centerOnUser();
  }
}
