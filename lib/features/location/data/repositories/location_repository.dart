import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/services/location_permission_flow.dart';
import 'package:partiu/features/location/domain/repositories/location_repository_interface.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:partiu/core/services/smart_geocoding_service.dart';

class LocationRepository implements LocationRepositoryInterface {
  
  final FirebaseFirestore _firestore;
  
  LocationRepository({FirebaseFirestore? firestore}) 
      : _firestore = firestore ?? FirebaseFirestore.instance;
  
  @override
  Future<bool> checkLocationPermission({
    required Function() onGpsDisabled,
    required Function() onDenied,
    required Function() onGranted,
  }) async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        onGpsDisabled();
        return false;
      }

      // Check location permission
      var permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await LocationPermissionFlow().request();
        if (permission == LocationPermission.denied) {
          onDenied();
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        onDenied();
        return false;
      }
      
      // Permission granted
      onGranted();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Future<Position> getUserCurrentLocation() async {
    try {
      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      
      return position;
    } on TimeoutException {
      throw TimeoutException('Location request timed out');
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }
  
  @override
  Future<Placemark> getUserAddress(double latitude, double longitude) async {
    try {
      final placemark = await SmartGeocodingService.instance.getAddressSmart(
        latitude: latitude,
        longitude: longitude,
      );
      
      if (placemark != null) {
        return placemark;
      } else {
        // Se retornou null, ou falhou API ou não tem dados anteriores.
        // Tenta um fallback force refresh ou lança
        throw Exception('No address found for the given coordinates (SmartGeo)');
      }
    } catch (e) {
      throw Exception('Failed to get address: $e');
    }
  }
  
  @override
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
  }) async {
    try {
      AppLogger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'LocationRepository');
      AppLogger.info('📤 SENDING TO API:', tag: 'LocationRepository');
      AppLogger.info('userId: $userId', tag: 'LocationRepository');
      AppLogger.info('lat: $latitude, lng: $longitude', tag: 'LocationRepository');
      AppLogger.info('geohash: $geohash', tag: 'LocationRepository');
      AppLogger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'LocationRepository');
      AppLogger.info('🌍 LOCATION FIELDS:', tag: 'LocationRepository');
      AppLogger.info('   country: "$country" (type: ${country.runtimeType}, isEmpty: ${country.isEmpty})', tag: 'LocationRepository');
      AppLogger.info('   locality: "$locality" (type: ${locality.runtimeType}, isEmpty: ${locality.isEmpty})', tag: 'LocationRepository');
      AppLogger.info('   state: "$state" (type: ${state.runtimeType}, isEmpty: ${state.isEmpty})', tag: 'LocationRepository');
      AppLogger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'LocationRepository');
      
      final userRef = _firestore.collection('Users').doc(userId);
      
      // 🔒 SEGURANÇA: Localização real vai para subcoleção privada
      // Apenas o próprio usuário e Cloud Functions podem acessar
      await userRef.collection('private').doc('location').set({
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Dados públicos (displayLatitude tem offset de ~1-3km para privacidade)
      await userRef.update({
        'displayLatitude': displayLatitude,
        'displayLongitude': displayLongitude,
        'geohash': geohash,
        'country': country,
        'locality': locality,
        'state': state,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      AppLogger.success('✅ Location updated (real → private, display → public)', tag: 'LocationRepository');
      AppLogger.success('updateUserLocation() SUCCESS', tag: 'LocationRepository');
      
    } catch (e) {
      AppLogger.error('❌ ERROR: $e', tag: 'LocationRepository');
      throw Exception('Failed to update user location: $e');
    }
  }
}
