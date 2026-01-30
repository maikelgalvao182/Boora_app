import 'package:partiu/plugins/locationpicker/entities/address_component.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


/// The result returned after completing location selection.
class LocationResult {
  /// The human readable name of the location. This is primarily the
  /// name of the road. But in cases where the place was selected from Nearby
  /// places list, we use the <b>name</b> provided on the list item.
  String? name; // or road

  /// The human readable locality of the location.
  String? locality;

  /// Latitude/Longitude of the selected location.
  LatLng? latLng;

  /// Formatted address suggested by Google
  String? formattedAddress;

  AddressComponent? country;

  AddressComponent? city;

  AddressComponent? administrativeAreaLevel1;

  AddressComponent? administrativeAreaLevel2;

  AddressComponent? subLocalityLevel1;

  AddressComponent? subLocalityLevel2;

  String? postalCode;

  String? placeId;

  /// Indica se a localização foi selecionada via mapa (arrastar/clicar)
  /// ao invés de busca. Quando true, não devemos mostrar endereço exato.
  bool isApproximateLocation = false;
}
