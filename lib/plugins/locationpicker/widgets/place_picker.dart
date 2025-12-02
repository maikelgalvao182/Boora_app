import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:partiu/plugins/locationpicker/entities/localization_item.dart';
import 'package:partiu/plugins/locationpicker/place_picker.dart';
import 'package:partiu/plugins/locationpicker/uuid.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Place picker widget made with map widget from
/// [google_maps_flutter](https://github.com/flutter/plugins/tree/master/packages/google_maps_flutter)
/// and other API calls to [Google Places API](https://developers.google.com/places/web-service/intro)
///
/// API key provided should have `Maps SDK for Android`, `Maps SDK for iOS`
/// and `Places API`  enabled for it
// ignore: must_be_immutable
class PlacePicker extends StatefulWidget {

  PlacePicker(
    this.apiKey, {
    super.key,
    this.displayLocation,
    this.localizationItem,
    LatLng? defaultLocation,
  }) {
    localizationItem ??= LocalizationItem();
    if (defaultLocation != null) {
      this.defaultLocation = defaultLocation;
    }
  }
  /// API key generated from Google Cloud Console. You can get an API key
  /// [here](https://cloud.google.com/maps-platform/)
  final String apiKey;

  /// Location to be displayed when screen is showed. If this is set or not null, the
  /// map does not pan to the user's current location.
  final LatLng? displayLocation;
  LocalizationItem? localizationItem;
  LatLng defaultLocation = const LatLng(10.5381264, 73.8827201);

  @override
  State<StatefulWidget> createState() => PlacePickerState();
}

/// Place picker state
class PlacePickerState extends State<PlacePicker> {
  // Simple HTTP client for Google Places requests
  final http.Client _httpClient = http.Client();
  final Completer<GoogleMapController> mapController = Completer();
  LatLng? _currentLocation;
  bool _loadMap = false;

  /// Indicator for the selected location
  final Set<Marker> markers = {};

  /// Result returned after user completes selection
  LocationResult? locationResult;

  /// Overlay to display autocomplete suggestions
  OverlayEntry? overlayEntry;

  List<NearbyPlace> nearbyPlaces = [];

  /// Session token required for autocomplete API call
  String sessionToken = Uuid().generateV4();

  GlobalKey appBarKey = GlobalKey();

  bool hasSearchTerm = false;

  String previousSearchTerm = '';

  // constructor
  // PlacePickerState();

  void onMapCreated(GoogleMapController controller) {
    mapController.complete(controller);
    moveToCurrentUserLocation();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    
    if (widget.displayLocation == null) {
      _getCurrentLocation()
          .then((value) {
            setState(() {
              _currentLocation = value;
            });
            setState(() {
              _loadMap = true;
            });
          })
          .catchError((e) {
            if (e is LocationServiceDisabledException) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _loadMap = true;
              });
            }
            //Navigator.of(context).pop(null);
          });
    } else {
      setState(() {
        markers.add(
          Marker(
            position: widget.displayLocation!,
            markerId: const MarkerId('selected-location'),
          ),
        );
        _loadMap = true;
      });
    }
  }

  @override
  void dispose() {
    overlayEntry?.remove();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (value, _) {
        if (Platform.isAndroid) {
          locationResult = null;
          _delayedPop();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          key: appBarKey,
          title: SearchInput(searchPlace),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child:
                  !_loadMap
                      ? const Center(child: CupertinoActivityIndicator(radius: 14))
                      : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target:
                              widget.displayLocation ??
                              _currentLocation ??
                              widget.defaultLocation,
                          zoom:
                              _currentLocation == null &&
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
                        if (Platform.isAndroid) {
                          _delayedPop();
                        } else {
                          Navigator.of(context).pop(locationResult);
                        }
                      },
                      widget.localizationItem!.tapToSelectLocation,
                    ),
                    const Divider(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text(
                        widget.localizationItem!.nearBy,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children:
                            nearbyPlaces
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
      ),
    );
  }

  /// Hides the autocomplete overlay
  void clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry?.remove();
      overlayEntry = null;
    }
  }

  /// Begins the search process by displaying a "wait" overlay then
  /// proceeds to fetch the autocomplete list. The bottom "dialog"
  /// is hidden so as to give more room and better experience for the
  /// autocomplete list overlay.
  void searchPlace(String place) {
    // on keyboard dismissal, the search was being triggered again
    // this is to cap that.
    if (place == previousSearchTerm) {
      return;
    }

    previousSearchTerm = place;

    // if (context == null) {
    //   return;
    // }

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
      builder:
          (context) => Positioned(
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
                        widget.localizationItem!.findingPlace,
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

  /// Fetches the place autocomplete list with the query [place].
  Future<void> autoCompleteSearch(String place) async {
    try {
      place = place.replaceAll(' ', '+');

      var endpoint =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?'
          'key=${widget.apiKey}&'
          'language=${widget.localizationItem!.languageCode}&'
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

      if (responseJson['status'] != null && responseJson['status'] != 'OK' && responseJson['status'] != 'ZERO_RESULTS') {
        throw Exception('Autocomplete API error: ${responseJson['status']}');
      }

      if (responseJson['predictions'] == null) {
        throw Error();
      }

      final List<dynamic> predictions = responseJson['predictions'];

      final suggestions = <RichSuggestion>[];

      if (predictions.isEmpty) {
        final aci = AutoCompleteItem();
        aci.text = widget.localizationItem!.noResultsFound;
        aci.offset = 0;
        aci.length = 0;

        suggestions.add(RichSuggestion(aci, () {}));
      } else {
        for (final dynamic t in predictions) {
          final aci =
              AutoCompleteItem()
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
      // Log error for debugging
      if (e.toString().contains('DioException')) {
      }
    }
  }

  /// To navigate to the selected place from the autocomplete list to the map,
  /// the lat,lng is required. This method fetches the lat,lng of the place and
  /// proceeds to moving the map to that location.
  Future<void> decodeAndSelectPlace(String placeId) async {
    clearOverlay();

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?key=${widget.apiKey}&language=${widget.localizationItem!.languageCode}&placeid=$placeId',
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
    }
  }

  /// Display autocomplete suggestions with the overlay.
  void displayAutoCompleteSuggestions(List<RichSuggestion> suggestions) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size;

    final appBarBox =
        appBarKey.currentContext?.findRenderObject() as RenderBox?;

    clearOverlay();

    overlayEntry = OverlayEntry(
      builder:
          (context) => Positioned(
            width: size?.width,
            top: appBarBox?.size.height,
            child: Material(elevation: 1, child: Column(children: suggestions)),
          ),
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  /// Utility function to get clean readable name of a location. First checks
  /// for a human-readable name from the nearby list. This helps in the cases
  /// that the user selects from the nearby list (and expects to see that as a
  /// result, instead of road name). If no name is found from the nearby list,
  /// then the road name returned is used instead.
  String getLocationName() {
    if (locationResult == null) {
      return widget.localizationItem!.unnamedLocation;
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

  /// Moves the marker to the indicated lat,lng
  void setMarker(LatLng latLng) {
    // markers.clear();
    setState(() {
      markers.clear();
      markers.add(
        Marker(markerId: const MarkerId('selected-location'), position: latLng),
      );
    });
  }

  /// Fetches and updates the nearby places to the provided lat,lng
  Future<void> getNearbyPlaces(LatLng latLng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
        'key=${widget.apiKey}&location=${latLng.latitude},${latLng.longitude}'
        '&radius=150&language=${widget.localizationItem!.languageCode}',
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
        final nearbyPlace =
            NearbyPlace()
              ..name = item['name']
              ..icon = item['icon']
              ..latLng = LatLng(
                item['geometry']['location']['lat'],
                item['geometry']['location']['lng'],
              );

        nearbyPlaces.add(nearbyPlace);
      }

      // to update the nearby places
      setState(() {
        // this is to require the result to show
        hasSearchTerm = false;
      });
    } catch (e) {
    }
  }

  /// This method gets the human readable name of the location. Mostly appears
  /// to be the road name and the locality.
  Future<void> reverseGeocodeLatLng(LatLng latLng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?'
        'latlng=${latLng.latitude},${latLng.longitude}&'
        'language=${widget.localizationItem!.languageCode}&'
        'key=${widget.apiKey}',
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
          // Check if route already ends with the street number to avoid duplication
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
        locationResult =
            LocationResult()
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
    }
  }

  /// Moves the camera to the provided location and updates other UI features to
  /// match the location.
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
    if (_currentLocation != null) {
      moveToLocation(_currentLocation!);
    } else {
      moveToLocation(widget.defaultLocation);
    }
  }

  Future<LatLng> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;
    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.

      final isOk = await Future(
        () => _showLocationDisabledAlertDialog(context),
      );
      if (isOk ?? false) {
        return Future.error(const LocationServiceDisabledException());
      } else {
        return Future.error('Location Services is not enabled');
      }
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      //return widget.defaultLocation;
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }
    try {
      final locationData = await Geolocator.getCurrentPosition();
      final target = LatLng(locationData.latitude, locationData.longitude);
      //moveToLocation(target);
      return target;
    } on TimeoutException {
      final locationData = await Geolocator.getLastKnownPosition();
      if (locationData != null) {
        return LatLng(locationData.latitude, locationData.longitude);
      } else {
        return widget.defaultLocation;
      }
    }
  }

  Future<bool?> _showLocationDisabledAlertDialog(BuildContext context) {
    if (Platform.isIOS) {
      return showCupertinoDialog(
        context: context,
        builder: (BuildContext ctx) {
          return CupertinoAlertDialog(
            title: const Text('Location is disabled'),
            content: const Text(
              'To use location, go to your Settings App > Privacy > Location Services.',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              CupertinoDialogAction(
                child: const Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
    } else {
      return showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('Location is disabled'),
            content: const Text(
              'The app needs to access your location. Please enable location service.',
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () async {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                  Future(() => Navigator.of(context).pop(true));
                },
              ),
            ],
          );
        },
      );
    }
  }

  // add delay to the map pop to avoid `Fatal Exception: java.lang.NullPointerException` error on Android
  Future<bool> _delayedPop() async {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
    pageBuilder:
      (context, animation, secondaryAnimation) => const PopScope(
              canPop: false,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(child: CupertinoActivityIndicator(radius: 14)),
              ),
            ),
        transitionDuration: Duration.zero,
        barrierColor: Colors.black45,
        opaque: false,
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));
    Future(
      () =>
          Navigator.of(context)
            ..pop()
            ..pop(locationResult),
    );
    return Future.value(false);
  }
}
