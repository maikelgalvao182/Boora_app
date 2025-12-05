import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/widgets/nearby_places_carousel.dart';
import 'package:partiu/features/home/presentation/widgets/place_card/place_card_controller.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Card que exibe informações de localização de um evento
class PlaceCard extends StatefulWidget {
  const PlaceCard({
    required this.controller,
    super.key,
    this.onTap,
    this.customTagWidget,
  });

  final PlaceCardController controller;
  final VoidCallback? onTap;
  final Widget? customTagWidget;

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  late PlaceCardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_controller.isLoading) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: const Center(
          child: CupertinoActivityIndicator(radius: 16),
        ),
      );
    }

    // Error state
    if (_controller.error != null) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            _controller.error!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // No data
    if (!_controller.hasData) {
      return const SizedBox.shrink();
    }

    // Success state
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Name (clicável) + Tag
            GestureDetector(
              onTap: () => _openGoogleMaps(_controller.placeId),
              child: Row(
                children: [
                  const Icon(
                    Iconsax.link_2,
                    size: 16,
                    color: GlimpseColors.primaryDarker,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _controller.locationName ?? '',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: GlimpseColors.primaryColorLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.customTagWidget != null) ...[
                    const SizedBox(width: 8),
                    widget.customTagWidget!,
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 4),
            
            // Formatted Address (clicável)
            if (_controller.formattedAddress != null) ...[
              GestureDetector(
                onTap: () => _openGoogleMaps(_controller.placeId),
                child: Text(
                  _controller.formattedAddress!,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: GlimpseColors.textSubTitle,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Photos Carousel (clicável)
            if (_controller.photoUrls.isNotEmpty) ...[
              GestureDetector(
                onTap: () => _openGoogleMaps(_controller.placeId),
                child: SelectedPlacePhotosCarousel(
                  photoUrls: _controller.photoUrls,
                  placeName: _controller.locationName ?? '',
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Visitors Section
            if (_controller.visitors.isNotEmpty) ...[
              _buildVisitorsSection(),
            ],
          ],
        ),
      ),
    );
  }

  /// Constrói a seção de visitantes com avatares empilhados
  Widget _buildVisitorsSection() {
    final visitors = _controller.visitors;
    final totalCount = _controller.totalVisitorsCount;
    final othersCount = totalCount - visitors.length;
    
    // Calcular largura e altura necessárias para os avatares empilhados
    const avatarSize = 22.0; // Aumentado de 18 para 22 (+ 4px)
    const avatarOverlap = 14.0; // Ajustado proporcionalmente
    final stackWidth = avatarSize + ((visitors.length - 1) * avatarOverlap);

    return Row(
      children: [
        // Avatares empilhados
        SizedBox(
          width: stackWidth,
          height: avatarSize,
          child: Stack(
            clipBehavior: Clip.none, // Permite que os avatares não sejam cortados
            children: [
              for (int i = 0; i < visitors.length; i++)
                Positioned(
                  left: i * avatarOverlap,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: StableAvatar(
                      userId: visitors[i]['userId'] as String,
                      photoUrl: visitors[i]['photoUrl'] as String?,
                      size: avatarSize,
                      enableNavigation: false,
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Texto "Visitado por..."
        Expanded(
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.textSubTitle,
              ),
              children: _buildVisitorsTextSpans(visitors, othersCount),
            ),
          ),
        ),
      ],
    );
  }

  /// Constrói os TextSpans para "Visitado por Nome1, Nome2 & xx outros" com cores diferentes
  List<TextSpan> _buildVisitorsTextSpans(List<Map<String, dynamic>> visitors, int othersCount) {
    final names = visitors
        .map((v) => v['fullName'] as String? ?? 'Usuário')
        .toList();

    if (names.isEmpty) return [];

    final spans = <TextSpan>[
      TextSpan(text: 'Visitado por '),
    ];

    if (names.length == 1) {
      spans.add(TextSpan(
        text: names[0],
        style: const TextStyle(color: GlimpseColors.primaryColorLight),
      ));
      if (othersCount > 0) {
        spans.add(TextSpan(text: ' & $othersCount outros'));
      }
      return spans;
    }

    if (names.length == 2) {
      spans.add(TextSpan(
        text: names[0],
        style: const TextStyle(color: GlimpseColors.primaryColorLight),
      ));
      if (othersCount > 0) {
        spans.add(TextSpan(text: ', '));
        spans.add(TextSpan(
          text: names[1],
          style: const TextStyle(color: GlimpseColors.primaryColorLight),
        ));
        spans.add(TextSpan(text: ' & $othersCount outros'));
      } else {
        spans.add(TextSpan(text: ' & '));
        spans.add(TextSpan(
          text: names[1],
          style: const TextStyle(color: GlimpseColors.primaryColorLight),
        ));
      }
      return spans;
    }

    // 3 ou mais
    spans.add(TextSpan(
      text: names[0],
      style: const TextStyle(color: GlimpseColors.primaryColorLight),
    ));
    spans.add(TextSpan(text: ', '));
    spans.add(TextSpan(
      text: names[1],
      style: const TextStyle(color: GlimpseColors.primaryColorLight),
    ));
    spans.add(TextSpan(text: ' & ${othersCount + (names.length - 2)} outros'));

    return spans;
  }

  /// Abre Google Maps com o placeId
  Future<void> _openGoogleMaps(String? placeId) async {
    if (placeId == null) return;
    
    final url = Uri.parse('https://www.google.com/maps/place/?q=place_id:$placeId');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('❌ Não foi possível abrir Google Maps: $url');
    }
  }
}
