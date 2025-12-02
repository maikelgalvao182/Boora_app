class AddressComponent {

  AddressComponent({this.name, this.shortName});
  String? name;
  String? shortName;

  static AddressComponent fromJson(dynamic json) {
    return AddressComponent(name: json['long_name'], shortName: json['short_name']);
  }
}
