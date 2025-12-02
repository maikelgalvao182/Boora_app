import 'package:partiu/plugins/locationpicker/entities/entities.dart' show LocationResult;
import 'package:partiu/plugins/locationpicker/entities/location_result.dart' show LocationResult;
import 'package:partiu/plugins/locationpicker/place_picker.dart' show LocationResult;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Nearby place data will be deserialized into this model.
class NearbyPlace {
  /// The human-readable name of the location provided. This value is provided
  /// for [LocationResult.name] when the user selects this nearby place.
  String? name;

  /// The icon identifying the kind of place provided. Eg. lodging, chapel,
  /// hospital, etc.
  String? icon;

  // Latitude/Longitude of the provided location.
  LatLng? latLng;
  
  /// Photo reference from Google Places API
  String? photoReference;
  
  /// Photo width
  int? photoWidth;
  
  /// Photo height
  int? photoHeight;
}
