import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/features/home/data/models/map_bounds.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';

class MapPeopleController {
  final PeopleMapDiscoveryService _service = PeopleMapDiscoveryService();

  void setViewportActive(bool active) {
    _service.setViewportActive(active);
  }

  Future<void> loadPeopleCountInBounds(MapBounds bounds) async {
    await _service.loadPeopleCountInBounds(bounds);
  }

  Future<void> forceRefresh(MapBounds bounds) async {
    await _service.forceRefresh(bounds);
  }

  Future<void> onCameraIdle(LatLngBounds visibleRegion, double zoom, double clusterZoomThreshold) async {
    final viewportActive = zoom > clusterZoomThreshold;
    _service.setViewportActive(viewportActive);
    if (viewportActive) {
      final bounds = MapBounds.fromLatLngBounds(visibleRegion);
      await _service.loadPeopleCountInBounds(bounds);
    }
  }
}
