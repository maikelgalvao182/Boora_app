import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/typing_indicator.dart';

/// Botão flutuante "Perto de você" com avatares empilhados
class PeopleButton extends StatefulWidget {
  const PeopleButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  State<PeopleButton> createState() => _PeopleButtonState();
}

class _PeopleButtonState extends State<PeopleButton> {
  final PeopleMapDiscoveryService _peopleCountService = PeopleMapDiscoveryService();
  late final ValueNotifier<app_user.User?> _cachedNearbyUser;

  @override
  void initState() {
    super.initState();

    _cachedNearbyUser = ValueNotifier<app_user.User?>(null);
    _peopleCountService.nearbyPeople.addListener(_updateCachedNearbyUser);

    // Seed imediato: ValueNotifier não notifica o valor atual ao adicionar listener.
    _updateCachedNearbyUser();
  }

  @override
  void dispose() {
    _peopleCountService.nearbyPeople.removeListener(_updateCachedNearbyUser);
    _cachedNearbyUser.dispose();
    super.dispose();
  }

  void _updateCachedNearbyUser() {
    final people = _peopleCountService.nearbyPeople.value;
    if (people.isEmpty) return;

    final first = people.first;
    final current = _cachedNearbyUser.value;
    if (current?.userId == first.userId && current?.photoUrl == first.photoUrl) {
      return;
    }

    _cachedNearbyUser.value = first;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    final titleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: GlimpseColors.primaryColorLight,
    );

    final subtitleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: GlimpseColors.primary,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _peopleCountService.isViewportActive,
      builder: (context, viewportActive, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            AnimatedExpandable(
              isExpanded: !viewportActive,
              axis: Axis.horizontal,
              maintainState: true,
              clip: false,
              child: _ZoomInToSeePeopleButton(
                label: i18n.translate('zoom_in_to_see_people'),
                titleStyle: titleStyle,
                subtitleStyle: subtitleStyle,
              ),
            ),
            AnimatedExpandable(
              isExpanded: viewportActive,
              axis: Axis.horizontal,
              maintainState: true,
              clip: false,
              child: _PeopleNearYouButton(
                onPressed: widget.onPressed,
                peopleCountService: _peopleCountService,
                cachedUser: _cachedNearbyUser,
                i18n: i18n,
                titleStyle: titleStyle,
                subtitleStyle: subtitleStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ZoomInToSeePeopleButton extends StatelessWidget {
  const _ZoomInToSeePeopleButton({
    required this.label,
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final String label;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final full = label.trim();
    String line1 = full;
    String line2 = '';

    // Preferir quebra determinística (pt): "Aproxime o mapa" / "para carregar perfis"
    final splitToken = ' para ';
    final splitIdx = full.indexOf(splitToken);
    if (splitIdx > 0) {
      line1 = full.substring(0, splitIdx).trimRight();
      line2 = full.substring(splitIdx + 1).trimLeft(); // mantém "para ..."
    }

    // Fallback para outros idiomas: divide em duas linhas
    if (line2.isEmpty) {
      final words = full.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length >= 2) {
        final splitAt = (words.length / 2).ceil();
        line1 = words.take(splitAt).join(' ');
        line2 = words.skip(splitAt).join(' ');
      }
    }

    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(100),
      child: Container(
        height: 56,
        padding: const EdgeInsets.only(left: 8, right: 8),
        decoration: BoxDecoration(
          color: GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(100),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GlimpseColors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: Icon(
                Iconsax.search_normal,
                size: 20,
                color: GlimpseColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (line2.isNotEmpty)
                    Text(
                      line2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: GlimpseColors.primaryColorLight,
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleNearYouButton extends StatelessWidget {
  const _PeopleNearYouButton({
    required this.onPressed,
    required this.peopleCountService,
    required this.cachedUser,
    required this.i18n,
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final VoidCallback onPressed;
  final PeopleMapDiscoveryService peopleCountService;
  final ValueListenable<app_user.User?> cachedUser;
  final AppLocalizations i18n;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: peopleCountService.nearbyPeopleCount,
      builder: (context, boundsCount, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: peopleCountService.isLoading,
          builder: (context, isLoading, __) {
            return ValueListenableBuilder<List<app_user.User>>(
              valueListenable: peopleCountService.nearbyPeople,
              builder: (context, nearbyPeople, ___) {
                final count = boundsCount.clamp(0, 1 << 30);

                final peopleNearYouLabel = i18n.translate('people_near_you');
                final countTemplate = count == 1
                    ? i18n.translate('nearby_people_count_singular')
                    : i18n.translate('nearby_people_count_plural');
                final peopleCountLabel =
                    countTemplate.replaceAll('{count}', count.toString());

                const subtitleLineHeight = 14.0;

                final user = nearbyPeople.isNotEmpty ? nearbyPeople.first : null;

                return ValueListenableBuilder<app_user.User?>(
                  valueListenable: cachedUser,
                  builder: (context, cached, ____) {
                    final effectiveUser = user ?? cached;

                    return Material(
                      elevation: 8,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(100),
                      child: InkWell(
                        onTap: onPressed,
                        borderRadius: BorderRadius.circular(100),
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.only(left: 8, right: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (effectiveUser != null)
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: StableAvatar(
                                    userId: effectiveUser.userId,
                                    photoUrl: effectiveUser.photoUrl,
                                    size: 40,
                                    enableNavigation: false,
                                  ),
                                )
                              else if (isLoading)
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Center(
                                    child: CupertinoActivityIndicator(radius: 8),
                                  ),
                                )
                              else
                                const SizedBox(width: 40, height: 40),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    peopleNearYouLabel,
                                    style: titleStyle,
                                  ),
                                  if (isLoading)
                                    SizedBox(
                                      height: subtitleLineHeight,
                                      child: TypingIndicator(
                                        color: subtitleStyle.color ??
                                            GlimpseColors.primary,
                                        dotSize: 5,
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      height: subtitleLineHeight,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          peopleCountLabel,
                                          style: subtitleStyle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: GlimpseColors.primaryColorLight,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
