import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Widget isolado para o mapa
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    required this.initialLocation,
    this.selectedLocation,
    required this.onMapCreated,
    required this.onTap,
    this.onCameraIdle,
    this.onCameraMoveStarted,
    this.markers = const {},
    this.circles = const {},
  });

  final LatLng initialLocation;
  final LatLng? selectedLocation;
  final Function(GoogleMapController) onMapCreated;
  final ValueChanged<LatLng> onTap;
  final VoidCallback? onCameraIdle;
  final VoidCallback? onCameraMoveStarted;
  final Set<Marker> markers;
  final Set<Circle> circles;

  @override
  State<LocationPickerMap> createState() => LocationPickerMapState();
}

class LocationPickerMapState extends State<LocationPickerMap> {
  GoogleMapController? _controller;
  bool _controllerInitialized = false;

  /// Getter público para acesso ao controller
  GoogleMapController? get controller => _controller;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialLocation,
        zoom: 15,
      ),
      minMaxZoomPreference: const MinMaxZoomPreference(0, 16),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      buildingsEnabled: false,
      onMapCreated: (controller) {
        if (!_controllerInitialized) {
          _controller = controller;
          _controllerInitialized = true;
          widget.onMapCreated(controller);
        }
      },
      onTap: widget.onTap,
      onCameraIdle: widget.onCameraIdle,
      onCameraMoveStarted: widget.onCameraMoveStarted,
      markers: widget.markers,
      circles: widget.circles,
    );
  }

  /// Anima câmera para uma nova localização
  Future<void> animateToLocation(LatLng location) async {
    if (_controller == null || !_controllerInitialized) return;
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: location, zoom: 15),
      ),
    );
  }

  /// Move câmera instantaneamente (sem animação) - usado na inicialização
  void setInitialCamera(LatLng target) {
    if (_controller == null || !_controllerInitialized) return;
    _controller?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 15),
      ),
    );
  }

  @override
  void dispose() {
    _controllerInitialized = false;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}
