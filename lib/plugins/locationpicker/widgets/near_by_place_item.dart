import 'package:partiu/plugins/locationpicker/place_picker.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NearbyPlaceItem extends StatelessWidget {
  static const String _apiKey = 'AIzaSyCykzqaHI74daUNLuQfXyRyNgZRTltz4Vc';

  const NearbyPlaceItem(this.nearbyPlace, this.onTap, {super.key});
  final NearbyPlace nearbyPlace;
  final VoidCallback onTap;

  String? _getPhotoUrl() {
    if (nearbyPlace.photoReference != null) {
      return 'https://maps.googleapis.com/maps/api/place/photo?'
          'maxwidth=400&'
          'photoreference=${nearbyPlace.photoReference}&'
          'key=$_apiKey';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _getPhotoUrl();
    
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: <Widget>[
              // Foto ou ícone
              if (photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: Icon(Icons.place, color: Colors.grey[400], size: 30),
                    ),
                  ),
                )
              else
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: nearbyPlace.icon != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Image.network(
                            nearbyPlace.icon!,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.place, color: Colors.grey[400]);
                            },
                          ),
                        )
                      : Icon(Icons.place, color: Colors.grey[400], size: 30),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${nearbyPlace.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
