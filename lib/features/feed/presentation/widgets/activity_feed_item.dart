import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/feed/data/models/activity_feed_item_model.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';
import 'package:partiu/shared/utils/date_formatter.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Widget para exibir um item do feed de atividades (evento criado)
/// 
/// Layout igual ao EventPhotoFeedItem:
/// - Header: [Avatar] [Nome > Quer Atividade Emoji TimeAgo]
/// - Location em linha separada
/// - Container com emoji (como se fosse imagem)
class ActivityFeedItem extends StatelessWidget {
  const ActivityFeedItem({
    super.key,
    required this.item,
    this.onTap,
  });

  final ActivityFeedItemModel item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                StableAvatar(
                  userId: item.userId,
                  size: 38,
                  photoUrl: item.userPhotoUrl,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Nome > Quer Atividade Emoji TimeAgo
                      Text.rich(
                        TextSpan(
                          children: [
                            // Nome do usuário com badge
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: ReactiveUserNameWithBadge(
                                userId: item.userId,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: GlimpseColors.primaryColorLight,
                                ),
                              ),
                            ),
                            // Separador >
                            TextSpan(
                              text: ' > ',
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: GlimpseColors.textSubTitle,
                              ),
                            ),
                            // "Quer" + Activity name + Emoji
                            TextSpan(
                              text: '${i18n.translate('feed_action_wants')} ${item.activityText} ${item.emoji}',
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: GlimpseColors.primary,
                              ),
                            ),
                            // Time ago
                            if (item.createdAt != null)
                              TextSpan(
                                text: ' ${TimeAgoHelper.format(context, timestamp: item.createdAt!.toDate(), short: true)}',
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: GlimpseColors.textSubTitle,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Location + Data (linha separada)
                      Row(
                        children: [
                          const Icon(
                            IconsaxPlusLinear.location,
                            size: 14,
                            color: GlimpseColors.textSubTitle,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${item.locationName} • ${DateFormatter.formatDate(item.eventDate.toDate())}',
                              style: GoogleFonts.getFont(
                                FONT_PLUS_JAKARTA_SANS,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: GlimpseColors.textSubTitle,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Container do emoji (como imagem) - com recuo igual ao post comum (avatar 38 + spacing 10)
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  height: 180,
                  color: MarkerColorHelper.getColorForId(item.eventId),
                  child: Stack(
                    children: [
                      // Imagem de overlay com 50% opacidade
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.1,
                          child: Image.asset(
                            'assets/images/map.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      // Emoji centralizado com container redondo com borda pontilhada branca
                      Center(
                        child: CustomPaint(
                          painter: _DashedCirclePainter(
                            color: Colors.white,
                            strokeWidth: 4,
                            dashWidth: 8,
                            dashSpace: 5,
                          ),
                          child: Container(
                            width: 100,
                            height: 100,
                            alignment: Alignment.center,
                            child: Text(
                              item.emoji,
                              style: const TextStyle(
                                fontSize: 52,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter para desenhar círculo com borda pontilhada
class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashWidth = 5,
    this.dashSpace = 3,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * 3.14159 * radius;
    final dashCount = (circumference / (dashWidth + dashSpace)).floor();
    final actualDashSpace = (circumference - (dashCount * dashWidth)) / dashCount;
    
    for (var i = 0; i < dashCount; i++) {
      final startAngle = (i * (dashWidth + actualDashSpace)) / radius;
      final sweepAngle = dashWidth / radius;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
