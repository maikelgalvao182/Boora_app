import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/plugins/locationpicker/entities/localization_item.dart';
import 'package:partiu/plugins/locationpicker/place_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:partiu/core/services/smart_geocoding_service.dart';

/// Service para comunicação com Google Places API
class PlaceService {
  PlaceService({
    required this.apiKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _httpClient;
  
  // Cache curto para autocomplete (60s)
  final Map<String, _CachedPlaceResults> _autocompleteCache = {};

  /// Autocomplete de lugares
  Future<List<RichSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
    required LocalizationItem localization,
    LatLng? bias,
    String? countryCode,
  }) async {
    // 1) Mínimo de 3 caracteres (Regra de Ouro)
    if (query.trim().length < 3) {
      return [];
    }

    // 2) Verificar Cache (ROI alto para backspace/redo)
    if (_autocompleteCache.containsKey(query)) {
      final cached = _autocompleteCache[query]!;
      // Cache válido por 60 segundos
      if (DateTime.now().difference(cached.timestamp).inSeconds < 60) {
        return cached.suggestions;
      }
    }

    try {
      final normalizedCountryCode = (countryCode ?? '').trim().toLowerCase();

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        <String, String>{
          'key': apiKey,
          'language': localization.languageCode,
          'input': query,
          'sessiontoken': sessionToken,
          if (normalizedCountryCode.isNotEmpty)
            'components': 'country:$normalizedCountryCode',
          if (bias != null) ...{
            'location': '${bias.latitude},${bias.longitude}',
            // Bias suave para não “matar” resultados; também evita comportamento estranho sem radius.
            'radius': '50000',
          },
        },
      );

      final response = await _httpClient.get(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Autocomplete timeout'),
          );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          AppLogger.warning(
            'Places autocomplete HTTP ${response.statusCode}',
            tag: 'PLACES',
          );
        }
        throw Exception('Autocomplete failed: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (kDebugMode) {
        final status = responseJson['status'];
        if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
          AppLogger.warning(
            'Places autocomplete status=$status message=${responseJson['error_message'] ?? ''}',
            tag: 'PLACES',
          );
        }
      }

      if (responseJson['status'] != null &&
          responseJson['status'] != 'OK' &&
          responseJson['status'] != 'ZERO_RESULTS') {
        throw Exception('API error: ${responseJson['status']}');
      }

      if (responseJson['predictions'] == null) {
        return [];
      }

      final List<dynamic> predictions = responseJson['predictions'];

      if (predictions.isEmpty) {
        // Retornar lista vazia ao invés de item "no results found"
        return [];
      }

      final suggestions = predictions.map((t) {
        final matchedSubstrings = (t['matched_substrings'] as List<dynamic>?) ?? const [];
        final firstMatch = matchedSubstrings.isNotEmpty ? matchedSubstrings.first as Map<String, dynamic>? : null;

        final aci = AutoCompleteItem()
          ..id = t['place_id'] as String?
          ..text = t['description'] as String?
          ..offset = (firstMatch?['offset'] as num?)?.toInt() ?? 0
          ..length = (firstMatch?['length'] as num?)?.toInt() ?? 0;
        return RichSuggestion(aci, () {});
      }).toList();

      // 3) Cachear resultado
      _autocompleteCache[query] = _CachedPlaceResults(
        suggestions: suggestions,
        timestamp: DateTime.now(),
      );

      return suggestions;
    } catch (e) {
      if (kDebugMode) {
        AppLogger.warning(
          'Places autocomplete falhou: $e',
          tag: 'PLACES',
        );
      }
      return [];
    }
  }

  /// Busca detalhes completos de um lugar por ID
  /// Retorna name, formatted_address e coordenadas
  Future<LocationResult?> getPlaceDetails({
    required String placeId,
    required String languageCode,
  }) async {
    try {
      // ✅ SOLUÇÃO: Buscar campos essenciais (name, formatted_address, geometry)
      // Otimização: address_components removido para reduzir carga (Basic SKU)
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?'
        'key=$apiKey&'
        'language=$languageCode&'
        'fields=name,formatted_address,geometry,place_id&'
        'placeid=$placeId',
      );

      final response = await _httpClient.get(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Place details timeout'),
          );

      if (response.statusCode != 200) {
        throw Exception('Place details failed: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (responseJson['status'] != 'OK') {
        throw Exception('API error: ${responseJson['status']}');
      }

      final result = responseJson['result'] as Map<String, dynamic>;
      final location = result['geometry']['location'];
      final latLng = LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );

      // ✅ Extrair name e formatted_address
      final name = result['name'] as String?;
      final formattedAddress = result['formatted_address'] as String?;

      return LocationResult()
        ..name = name
        ..formattedAddress = formattedAddress
        ..latLng = latLng
        ..placeId = placeId;
        // Campos estruturados (city, state, etc) removidos para otimização
         
    } catch (e) {
      return null;
    }
  }

  /// Busca fotos de um lugar específico por placeId
  Future<List<String>> getPlacePhotos({
    required String placeId,
    required String languageCode,
  }) async {
    // Importante: fotos do Google Places (Photos API) desativadas no app.
    // Retornar sempre vazio evita chamadas extras e qualquer download indireto.
    return [];
  }

  /// Busca lugares próximos a uma localização
  Future<List<NearbyPlace>> getNearbyPlaces({
    required LatLng location,
    required String languageCode,
    int radius = 150,
  }) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
        'key=$apiKey&'
        'location=${location.latitude},${location.longitude}&'
        'radius=$radius&'
        'language=$languageCode',
      );

      final response = await _httpClient.get(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Nearby places timeout'),
          );

      if (response.statusCode != 200) {
        throw Exception('Nearby places failed: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (responseJson['status'] != 'OK') {
        return [];
      }

      final results = responseJson['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        return [];
      }

      return results.map((item) {
        return NearbyPlace()
          ..name = item['name'] as String?
          ..icon = item['icon'] as String?
          ..photoReference = null
          ..photoWidth = null
          ..photoHeight = null
          ..latLng = LatLng(
            (item['geometry']['location']['lat'] as num).toDouble(),
            (item['geometry']['location']['lng'] as num).toDouble(),
          );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Reverse geocoding - converte coordenadas em endereço
  Future<LocationResult?> reverseGeocode({
    required LatLng location,
    required String languageCode,
  }) async {
    try {
      // Usar SmartGeocodingService para cache e economia (Native Geocoder)
      final placemark = await SmartGeocodingService.instance.getAddressSmart(
        latitude: location.latitude,
        longitude: location.longitude,
      );

      if (placemark == null) return null;

      // Construir nome do local
      String name = placemark.name ?? '';
      if (placemark.thoroughfare != null && placemark.thoroughfare!.isNotEmpty) {
        if (placemark.subThoroughfare != null && placemark.subThoroughfare!.isNotEmpty) {
           name = '${placemark.thoroughfare}, ${placemark.subThoroughfare}';
        } else {
           name = placemark.thoroughfare!;
        }
      } else if (name.isEmpty) {
        // Fallback names
        name = placemark.subLocality ?? placemark.locality ?? placemark.administrativeArea ?? '';
      }

      // Construct formatted address like "Rua X, Bairro, Cidade, Estado, Pais"
      final parts = [
        name,
        placemark.subLocality,
        placemark.locality,
        placemark.administrativeArea,
        placemark.country
      ].where((e) => e != null && e.isNotEmpty).toSet().join(', '); // toSet clean duplicates

      final locality = placemark.locality ?? placemark.administrativeArea;
      final city = locality;

      return LocationResult()
        ..name = name
        ..locality = locality
        ..latLng = location
        ..formattedAddress = parts
        ..placeId = null // Nativo não retorna place_id do Google
        ..postalCode = placemark.postalCode
        ..country = AddressComponent(name: placemark.country, shortName: placemark.isoCountryCode)
        ..administrativeAreaLevel1 = AddressComponent(
          name: placemark.administrativeArea,
          shortName: placemark.administrativeArea,
        )
        ..administrativeAreaLevel2 = AddressComponent(
          name: placemark.subAdministrativeArea,
          shortName: placemark.subAdministrativeArea,
        )
        ..city = AddressComponent(name: city, shortName: city)
        ..subLocalityLevel1 = AddressComponent(
          name: placemark.subLocality,
          shortName: placemark.subLocality,
        );
    } catch (e) {
      AppLogger.error('Reverse geocode error: $e', tag: 'PlaceService');
      return null;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class _CachedPlaceResults {
  final List<RichSuggestion> suggestions;
  final DateTime timestamp;

  _CachedPlaceResults({
    required this.suggestions,
    required this.timestamp,
  });
}
