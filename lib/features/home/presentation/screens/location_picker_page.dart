import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/plugins/locationpicker/entities/location_result.dart';
import 'package:partiu/plugins/locationpicker/entities/localization_item.dart';
import 'package:partiu/plugins/locationpicker/place_picker.dart';
import 'package:partiu/plugins/locationpicker/uuid.dart';

/// Full-screen location picker page for activity creation
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({
    super.key,
    this.displayLocation,
    this.localizationItem,
    this.defaultLocation = const LatLng(-23.5505, -46.6333), // São Paulo
  });

  final LatLng? displayLocation;
  final LocalizationItem? localizationItem;
  final LatLng defaultLocation;

  @override
  State<StatefulWidget> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const String _apiKey = 'AIzaSyCykzqaHI74daUNLuQfXyRyNgZRTltz4Vc';
  
  final http.Client _httpClient = http.Client();
  final Completer<GoogleMapController> mapController = Completer();
  LatLng? _currentLocation;
  bool _loadMap = false;

  final Set<Marker> markers = {};
  LocationResult? locationResult;
  OverlayEntry? overlayEntry;
  List<NearbyPlace> nearbyPlaces = [];
  String sessionToken = Uuid().generateV4();
  GlobalKey appBarKey = GlobalKey();
  bool hasSearchTerm = false;
  String previousSearchTerm = '';
  late LocalizationItem localizationItem;

  @override
  void initState() {
    super.initState();
    localizationItem = widget.localizationItem ?? LocalizationItem();
    
    // Carregar o mapa imediatamente sem esperar localização
    setState(() {
      _loadMap = true;
    });
    
    if (widget.displayLocation == null) {
      // Buscar localização em background
      _getCurrentLocation()
          .then((value) {
            if (mounted) {
              setState(() {
                _currentLocation = value;
              });
              moveToLocation(value);
            }
          })
          .catchError((e) {
            // Ignorar erros de localização, apenas usar localização padrão
            debugPrint('Erro ao obter localização: $e');
          });
    } else {
      setState(() {
        markers.add(
          Marker(
            position: widget.displayLocation!,
            markerId: const MarkerId('selected-location'),
          ),
        );
      });
      moveToLocation(widget.displayLocation!);
    }
  }

  @override
  void dispose() {
    overlayEntry?.remove();
    _httpClient.close();
    super.dispose();
  }

  void onMapCreated(GoogleMapController controller) {
    mapController.complete(controller);
    moveToCurrentUserLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        key: appBarKey,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: SearchInput(searchPlace),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: !_loadMap
                ? const Center(child: CupertinoActivityIndicator(radius: 14))
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.displayLocation ??
                          _currentLocation ??
                          widget.defaultLocation,
                      zoom: _currentLocation == null &&
                              widget.displayLocation == null
                          ? 5
                          : 15,
                    ),
                    minMaxZoomPreference: const MinMaxZoomPreference(0, 16),
                    myLocationEnabled: true,
                    buildingsEnabled: false,
                    onMapCreated: onMapCreated,
                    onTap: (latLng) {
                      clearOverlay();
                      moveToLocation(latLng);
                    },
                    markers: markers,
                  ),
          ),
          if (!hasSearchTerm)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectPlaceAction(
                    getLocationName(),
                    () {
                      Navigator.of(context).pop(locationResult);
                    },
                    localizationItem.tapToSelectLocation,
                  ),
                  const Divider(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Text(
                      localizationItem.nearBy,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: nearbyPlaces
                          .map(
                            (it) => NearbyPlaceItem(it, () {
                              if (it.latLng != null) {
                                moveToLocation(it.latLng!);
                              }
                            }),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry?.remove();
      overlayEntry = null;
    }
  }

  void searchPlace(String place) {
    if (place == previousSearchTerm) {
      return;
    }

    previousSearchTerm = place;

    clearOverlay();

    setState(() {
      hasSearchTerm = place.isNotEmpty;
    });

    if (place.isEmpty) {
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size;

    final appBarBox =
        appBarKey.currentContext?.findRenderObject() as RenderBox?;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarBox?.size.height,
        width: size?.width,
        child: Material(
          elevation: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 24,
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  height: 24,
                  width: 24,
                  child: CupertinoActivityIndicator(radius: 14),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    localizationItem.findingPlace,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry!);

    autoCompleteSearch(place);
  }

  Future<void> autoCompleteSearch(String place) async {
    try {
      place = place.replaceAll(' ', '+');

      var endpoint =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?'
          'key=$_apiKey&'
          'language=${localizationItem.languageCode}&'
          'input=$place&sessiontoken=$sessionToken';

      if (locationResult != null) {
        endpoint +=
            '&location=${locationResult!.latLng?.latitude},'
            '${locationResult!.latLng?.longitude}';
      }

      final response = await _httpClient.get(Uri.parse(endpoint)).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Autocomplete request timeout');
            },
          );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch autocomplete: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (responseJson['status'] != null &&
          responseJson['status'] != 'OK' &&
          responseJson['status'] != 'ZERO_RESULTS') {
        throw Exception('Autocomplete API error: ${responseJson['status']}');
      }

      if (responseJson['predictions'] == null) {
        throw Error();
      }

      final List<dynamic> predictions = responseJson['predictions'];

      final suggestions = <RichSuggestion>[];

      if (predictions.isEmpty) {
        final aci = AutoCompleteItem();
        aci.text = localizationItem.noResultsFound;
        aci.offset = 0;
        aci.length = 0;

        suggestions.add(RichSuggestion(aci, () {}));
      } else {
        for (final dynamic t in predictions) {
          final aci = AutoCompleteItem()
            ..id = t['place_id']
            ..text = t['description']
            ..offset = t['matched_substrings'][0]['offset']
            ..length = t['matched_substrings'][0]['length'];

          suggestions.add(
            RichSuggestion(aci, () {
              FocusScope.of(context).requestFocus(FocusNode());
              decodeAndSelectPlace(aci.id!);
            }),
          );
        }
      }

      displayAutoCompleteSuggestions(suggestions);
    } catch (e) {
      // Silent error handling
    }
  }

  Future<void> decodeAndSelectPlace(String placeId) async {
    clearOverlay();

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?key=$_apiKey&language=${localizationItem.languageCode}&placeid=$placeId',
      );

      final response = await _httpClient.get(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Place details request timeout');
            },
          );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch place details: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (responseJson['status'] != null && responseJson['status'] != 'OK') {
        throw Exception('Place Details API error: ${responseJson['status']}');
      }

      if (responseJson['result'] == null) {
        throw Error();
      }

      final location = responseJson['result']['geometry']['location'];
      if (mapController.isCompleted) {
        moveToLocation(LatLng(location['lat'], location['lng']));
      }
    } catch (e) {
      // Silent error handling
    }
  }

  void displayAutoCompleteSuggestions(List<RichSuggestion> suggestions) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size;

    final appBarBox =
        appBarKey.currentContext?.findRenderObject() as RenderBox?;

    clearOverlay();

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
            width: size?.width,
            top: appBarBox?.size.height,
            child: Material(elevation: 1, child: Column(children: suggestions)),
          ),
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  String getLocationName() {
    if (locationResult == null) {
      return localizationItem.unnamedLocation;
    }

    for (final np in nearbyPlaces) {
      if (np.latLng == locationResult?.latLng &&
          np.name != locationResult?.locality) {
        locationResult?.name = np.name;
        return '${np.name}, ${locationResult?.locality}';
      }
    }

    return '${locationResult?.name}, ${locationResult?.locality}';
  }

  void setMarker(LatLng latLng) {
    setState(() {
      markers.clear();
      markers.add(
        Marker(markerId: const MarkerId('selected-location'), position: latLng),
      );
    });
  }

  Future<void> getNearbyPlaces(LatLng latLng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
        'key=$_apiKey&location=${latLng.latitude},${latLng.longitude}'
        '&radius=150&language=${localizationItem.languageCode}',
      );

      final response = await _httpClient.get(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Nearby places request timeout');
            },
          );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch nearby places: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (responseJson['status'] != null && responseJson['status'] != 'OK') {
        throw Exception('Places API error: ${responseJson['status']}');
      }

      if (responseJson['results'] == null) {
        throw Error();
      }

      nearbyPlaces.clear();

      for (final Map<String, dynamic> item in responseJson['results']) {
        String? photoReference;
        int? photoWidth;
        int? photoHeight;
        
        // Extrair primeira foto se disponível
        if (item['photos'] != null && item['photos'].isNotEmpty) {
          final photo = item['photos'][0];
          photoReference = photo['photo_reference'];
          photoWidth = photo['width'];
          photoHeight = photo['height'];
        }
        
        final nearbyPlace = NearbyPlace()
          ..name = item['name']
          ..icon = item['icon']
          ..photoReference = photoReference
          ..photoWidth = photoWidth
          ..photoHeight = photoHeight
          ..latLng = LatLng(
            item['geometry']['location']['lat'],
            item['geometry']['location']['lng'],
          );

        nearbyPlaces.add(nearbyPlace);
      }

      setState(() {
        hasSearchTerm = false;
      });
    } catch (e) {
      // Silent error handling
    }
  }

  Future<void> reverseGeocodeLatLng(LatLng latLng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?'
        'latlng=${latLng.latitude},${latLng.longitude}&'
        'language=${localizationItem.languageCode}&'
        'key=$_apiKey',
      );

      final response = await _httpClient.get(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Reverse geocode request timeout');
            },
          );

      if (response.statusCode != 200) {
        throw Exception('Failed to reverse geocode: ${response.statusCode}');
      }

      final responseJson = json.decode(response.body) as Map<String, dynamic>;

      if (responseJson['status'] != null && responseJson['status'] != 'OK') {
        throw Exception('Geocoding API error: ${responseJson['status']}');
      }

      if (responseJson['results'] == null) {
        throw Error();
      }

      final result = responseJson['results'][0];

      setState(() {
        var name = '';
        String? streetNumber;
        String? route;
        String? locality;
        String? postalCode;
        String? country;
        String? administrativeAreaLevel1;
        String? administrativeAreaLevel2;
        String? city;
        String? subLocalityLevel1;
        String? subLocalityLevel2;

        if (result['address_components'] is List<dynamic> &&
            result['address_components'].length != null &&
            result['address_components'].length > 0) {
          for (var i = 0; i < result['address_components'].length; i++) {
            final tmp = result['address_components'][i];
            final types = tmp['types'] as List<dynamic>;
            final shortName = tmp['short_name'];

            if (types.contains('street_number')) {
              streetNumber = shortName;
            } else if (types.contains('route')) {
              route = shortName;
            } else if (types.contains('sublocality_level_1')) {
              subLocalityLevel1 = shortName;
            } else if (types.contains('sublocality_level_2')) {
              subLocalityLevel2 = shortName;
            } else if (types.contains('locality')) {
              locality = shortName;
            } else if (types.contains('administrative_area_level_2')) {
              administrativeAreaLevel2 = shortName;
            } else if (types.contains('administrative_area_level_1')) {
              administrativeAreaLevel1 = shortName;
            } else if (types.contains('country')) {
              country = shortName;
            } else if (types.contains('postal_code')) {
              postalCode = shortName;
            }
          }
        }

        if (route != null && streetNumber != null) {
          if (route.trim().endsWith(streetNumber)) {
            name = route;
          } else {
            name = '$route, $streetNumber';
          }
        } else if (route != null) {
          name = route;
        } else if (streetNumber != null) {
          name = streetNumber;
        } else if (result['address_components'] != null &&
            result['address_components'].length > 0) {
          name = result['address_components'][0]['short_name'];
        }
        locality = locality ?? administrativeAreaLevel1;
        city = locality;
        locationResult = LocationResult()
          ..name = name
          ..locality = locality
          ..latLng = latLng
          ..formattedAddress = result['formatted_address']
          ..placeId = result['place_id']
          ..postalCode = postalCode
          ..country = AddressComponent(name: country, shortName: country)
          ..administrativeAreaLevel1 = AddressComponent(
            name: administrativeAreaLevel1,
            shortName: administrativeAreaLevel1,
          )
          ..administrativeAreaLevel2 = AddressComponent(
            name: administrativeAreaLevel2,
            shortName: administrativeAreaLevel2,
          )
          ..city = AddressComponent(name: city, shortName: city)
          ..subLocalityLevel1 = AddressComponent(
            name: subLocalityLevel1,
            shortName: subLocalityLevel1,
          )
          ..subLocalityLevel2 = AddressComponent(
            name: subLocalityLevel2,
            shortName: subLocalityLevel2,
          );
      });
    } catch (e) {
      // Silent error handling
    }
  }

  void moveToLocation(LatLng latLng) {
    mapController.future.then((controller) {
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 15),
        ),
      );
    });

    setMarker(latLng);
    reverseGeocodeLatLng(latLng);
    getNearbyPlaces(latLng);
  }

  Future<void> moveToCurrentUserLocation() async {
    if (widget.displayLocation != null) {
      moveToLocation(widget.displayLocation!);
      return;
    }
    
    // Usar localização atual se disponível, senão usar padrão
    final location = _currentLocation ?? widget.defaultLocation;
    moveToLocation(location);
  }

  Future<LatLng> _getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;
      
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return widget.defaultLocation;
      }
      
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return widget.defaultLocation;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        return widget.defaultLocation;
      }
      
      final locationData = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return LatLng(locationData.latitude, locationData.longitude);
    } catch (e) {
      debugPrint('Erro ao obter localização: $e');
      // Tentar última localização conhecida
      try {
        final locationData = await Geolocator.getLastKnownPosition();
        if (locationData != null) {
          return LatLng(locationData.latitude, locationData.longitude);
        }
      } catch (e) {
        debugPrint('Erro ao obter última localização: $e');
      }
      return widget.defaultLocation;
    }
  }
}
