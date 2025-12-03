import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Carousel horizontal com swipe de fotos do lugar selecionado
class SelectedPlacePhotosCarousel extends StatelessWidget {
  const SelectedPlacePhotosCarousel({
    super.key,
    required this.photoUrls,
    required this.placeName,
  });

  final List<String> photoUrls; // Agora recebe URLs reais
  final String placeName;

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 180,
      margin: const EdgeInsets.only(top: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: photoUrls.length,
        itemBuilder: (context, index) {
          final photoUrl = photoUrls[index]; // Usar URL diretamente

          return Container(
            width: 260, // Largura dobrada (120 * 2 + margem)
            margin: EdgeInsets.only(
              right: index < photoUrls.length - 1 ? 12 : 0,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Imagem
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: const Radius.circular(20),
                      bottom: index == 0 ? Radius.zero : const Radius.circular(20),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[200],
                        child: Center(
                          child: CupertinoActivityIndicator(
                            radius: 12,
                            color: GlimpseColors.primary,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) {
                        debugPrint('❌ Erro ao carregar foto: $error');
                        return Container(
                          color: Colors.grey[200],
                          child: Icon(
                            Icons.place,
                            color: Colors.grey[400],
                            size: 48,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Nome do lugar
                if (index == 0) // Mostrar nome apenas no primeiro card
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.place,
                          size: 16,
                          color: GlimpseColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            placeName,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: GlimpseColors.primaryColorLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
