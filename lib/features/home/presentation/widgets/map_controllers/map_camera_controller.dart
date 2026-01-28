import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';

class MapCameraController {
  final MapViewModel viewModel;
  GoogleMapController? mapController;

  MapCameraController({required this.viewModel});

  void setController(GoogleMapController? controller) {
    mapController = controller;
  }

  Future<void> centerOnUser() async {
    await moveCameraToUserLocation();
  }

  Future<void> moveCameraToUserLocation({bool animate = true}) async {
    final result = await viewModel.getUserLocation();

    if (result.hasError) {
      ToastService.showInfo(message: result.errorMessage!);
    }

    await moveCameraTo(
      result.location.latitude,
      result.location.longitude,
      zoom: 12.0,
      animate: animate,
    );
  }

  Future<void> moveCameraTo(
    double lat,
    double lng, {
    double zoom = 14.0,
    bool animate = true,
  }) async {
    if (mapController == null) return;

    try {
      final update = CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: zoom,
        ),
      );

      if (animate) {
        await mapController!.animateCamera(update);
      } else {
        await mapController!.moveCamera(update);
      }
    } catch (e) {
      // Falha silenciosa
    }
  }

  Future<void> onClusterTap(LatLng position, int count, double currentZoom) async {
    debugPrint('🔍🔍🔍 _onClusterTap: position=$position, count=$count');
    
    if (mapController == null) return;

    final events = viewModel.events;
    
    if (events.isEmpty) {
       _zoomToPosition(position, count, currentZoom);
       return;
    }

    final safeCount = count.clamp(1, events.length);

    final sortedEvents = List<EventModel>.from(events)..sort((a, b) {
       final distA = (a.lat - position.latitude) * (a.lat - position.latitude) + 
                     (a.lng - position.longitude) * (a.lng - position.longitude);
       final distB = (b.lat - position.latitude) * (b.lat - position.latitude) + 
                     (b.lng - position.longitude) * (b.lng - position.longitude);
       return distA.compareTo(distB);
    });

    final clusterEvents = sortedEvents.take(safeCount).toList();
    
    if (clusterEvents.isEmpty) {
        _zoomToPosition(position, count, currentZoom);
        return;
    }

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;

    for (final e in clusterEvents) {
      if (e.lat < minLat) minLat = e.lat;
      if (e.lat > maxLat) maxLat = e.lat;
      if (e.lng < minLng) minLng = e.lng;
      if (e.lng > maxLng) maxLng = e.lng;
    }

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final isPoint = latSpan < 0.0001 && lngSpan < 0.0001;

    if (isPoint) {
       _zoomToPosition(position, count, currentZoom);
    } else {
       final bounds = LatLngBounds(
         southwest: LatLng(minLat, minLng),
         northeast: LatLng(maxLat, maxLng),
       );
       
       debugPrint('🔍 Cluster bounds calculado: $latSpan x $lngSpan');
       mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80.0));
    }
  }

  void _zoomToPosition(LatLng position, int count, double currentZoom) {
      final zoomIncrement = count <= 3 ? 3.0 : 2.0;
      final targetZoom = (currentZoom + zoomIncrement).clamp(0.0, 18.0);
      mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, targetZoom));
  }
}
