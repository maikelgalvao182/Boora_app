import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Card de mapa compartilhável para exibir localização de evento com Apple Maps.
class EventLocationMapCard extends StatelessWidget {
  const EventLocationMapCard({
    required this.latitude,
    required this.longitude,
    this.locationName,
    this.formattedAddress,
    this.onOpenMaps,
    this.openMapsLabel = 'Open in Maps',
    this.height = 200,
    super.key,
  });

  final double latitude;
  final double longitude;
  final String? locationName;
  final String? formattedAddress;
  final VoidCallback? onOpenMaps;
  final String openMapsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final title = (locationName ?? '').trim();
    final subtitle = (formattedAddress ?? '').trim();
    final hasHeader = title.isNotEmpty || subtitle.isNotEmpty;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      height: height,
      decoration: BoxDecoration(
        color: GlimpseColors.bgColorLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: GlimpseColors.borderColorLight,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: Column(
          children: [
            if (hasHeader)
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: GlimpseColors.borderColorLight,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: GlimpseColors.primaryColorLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: GlimpseColors.textSubTitle,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AppleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(latitude, longitude),
                        zoom: 15,
                      ),
                      annotations: {
                        Annotation(
                          annotationId: AnnotationId('event_location'),
                          position: LatLng(latitude, longitude),
                          infoWindow: InfoWindow(
                            title: title.isNotEmpty ? title : null,
                            snippet: subtitle.isNotEmpty ? subtitle : null,
                          ),
                        ),
                      },
                      mapType: MapType.standard,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      rotateGesturesEnabled: true,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                    ),
                  ),
                  if (onOpenMaps != null)
                    Positioned(
                      right: 12.w,
                      bottom: 12.h,
                      child: GestureDetector(
                        onTap: onOpenMaps,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 8.h,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8.r,
                                offset: Offset(0, 2.h),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                openMapsLabel,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: GlimpseColors.primary,
                                ),
                              ),
                              SizedBox(width: 4.w),
                              Icon(
                                IconsaxPlusLinear.export_1,
                                size: 16.sp,
                                color: GlimpseColors.primary,
                              ),
                            ],
                          ),
                        ),
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
}
