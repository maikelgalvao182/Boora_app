import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ClusteringBody extends StatefulWidget {
  /// Default Constructor.
  const ClusteringBody({super.key});

  @override
  State<StatefulWidget> createState() => ClusteringBodyState();
}

/// State of the clustering page.
class ClusteringBodyState extends State<ClusteringBody> {
  /// Default Constructor.
  ClusteringBodyState();

  /// Maximum amount of cluster managers.
  static const int _clusterManagerMaxCount = 2;

  /// Amount of markers to be added to the cluster manager at once.
  static const int _markersToAddToClusterManagerCount = 10;

  /// Google map controller.
  GoogleMapController? controller;

  /// Map of clusterManagers with identifier as the key.
  Map<ClusterManagerId, ClusterManager> clusterManagers =
      <ClusterManagerId, ClusterManager>{};

  /// Map of markers with identifier as the key.
  Map<MarkerId, Marker> markers = <MarkerId, Marker>{
    MarkerId('marker_0'): Marker(
      markerId: MarkerId('marker_0'),
      position: LatLng(41.0082, 28.9784),
      infoWindow: InfoWindow(title: 'Marker 0', snippet: 'Sultanahmet Square'),
    ),
    MarkerId('marker_1'): Marker(
      markerId: MarkerId('marker_1'),
      position: LatLng(41.0090, 28.9760),
      infoWindow: InfoWindow(title: 'Marker 1', snippet: 'Hagia Sophia'),
    ),
    MarkerId('marker_2'): Marker(
      markerId: MarkerId('marker_2'),
      position: LatLng(41.0086, 28.9730),
      infoWindow: InfoWindow(title: 'Marker 2', snippet: 'Blue Mosque'),
    ),

    // Yeni eklenen marker'lar
    MarkerId('marker_3'): Marker(
      markerId: MarkerId('marker_3'),
      position: LatLng(41.0150, 28.9750),
      infoWindow: InfoWindow(title: 'Marker 3', snippet: 'Topkapi Palace'),
    ),
    MarkerId('marker_4'): Marker(
      markerId: MarkerId('marker_4'),
      position: LatLng(41.0310, 28.9840),
      infoWindow: InfoWindow(title: 'Marker 4', snippet: 'Taksim Square'),
    ),
    MarkerId('marker_5'): Marker(
      markerId: MarkerId('marker_5'),
      position: LatLng(41.0200, 28.9675),
      infoWindow: InfoWindow(title: 'Marker 5', snippet: 'Galata Tower'),
    ),
    MarkerId('marker_6'): Marker(
      markerId: MarkerId('marker_6'),
      position: LatLng(41.0215, 28.9850),
      infoWindow: InfoWindow(title: 'Marker 6', snippet: 'Bosphorus Bridge'),
    ),
    MarkerId('marker_7'): Marker(
      markerId: MarkerId('marker_7'),
      position: LatLng(41.0340, 28.9940),
      infoWindow: InfoWindow(title: 'Marker 7', snippet: 'Ortaköy Mosque'),
    ),
  };

  /// Counter for added cluster manager ids.
  int _clusterManagerIdCounter = 1;

  /// Cluster that was tapped most recently.
  Cluster? lastCluster;

  void _onMapCreated(GoogleMapController controllerParam) {
    setState(() {
      controller = controllerParam;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    _addClusterManager();
    super.initState();
  }

  void _addClusterManager() {
    if (clusterManagers.length == _clusterManagerMaxCount) {
      return;
    }

    final String clusterManagerIdVal =
        'cluster_manager_id_$_clusterManagerIdCounter';
    _clusterManagerIdCounter++;
    final ClusterManagerId clusterManagerId = ClusterManagerId(
      clusterManagerIdVal,
    );

    final ClusterManager clusterManager = ClusterManager(
      clusterManagerId: clusterManagerId,
      onClusterTap:
          (Cluster cluster) => setState(() {
            lastCluster = cluster;
          }),
    );

    setState(() {
      clusterManagers[clusterManagerId] = clusterManager;
    });
    _addMarkersToCluster(clusterManager);
  }

  void _addMarkersToCluster(ClusterManager clusterManager) {
    for (int i = 0; i < _markersToAddToClusterManagerCount; i++) {
      // Add additional offset to longitude for each cluster manager to space
      // out markers in different cluster managers.

      markers.forEach((markerId, marker) {
        final newMarker = Marker(
          clusterManagerId: clusterManager.clusterManagerId,
          markerId: markerId,
          position: marker.position,
          infoWindow: InfoWindow(title: marker.infoWindow.title, snippet: '*'),
          onTap: () {},
        );

        markers[markerId] = newMarker;
      });
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: const CameraPosition(
        target: LatLng(41.0082, 28.9784),
        zoom: 12.0,
      ),
      markers: Set<Marker>.of(markers.values),
      clusterManagers: Set<ClusterManager>.of(clusterManagers.values),
    );
  }
}