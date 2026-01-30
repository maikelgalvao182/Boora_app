import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

abstract class LocationRepositoryInterface {
  Future<bool> checkLocationPermission({
    required Function() onGpsDisabled,
    required Function() onDenied,
    required Function() onGranted,
  });
  
  Future<Position> getUserCurrentLocation();
  
  Future<Placemark> getUserAddress(double latitude, double longitude);
  
  Future<void> updateUserLocation({
    required String userId,
    required double latitude,
    required double longitude,
    required double displayLatitude,
    required double displayLongitude,
    required String geohash,
    required String country,
    required String locality,
    required String state,
  });
}
