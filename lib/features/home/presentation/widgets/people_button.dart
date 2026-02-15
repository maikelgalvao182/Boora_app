import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'dart:math' as math;
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/services/people_map_discovery_service.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';
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
    
    if (kDebugMode) {
      print('[PeopleButton] initState - Inicializando widget');
    }

    _cachedNearbyUser = ValueNotifier<app_user.User?>(null);
    _peopleCountService.nearbyPeople.addListener(_updateCachedNearbyUser);
    _peopleCountService.isLoading.addListener(_logLoadingState);
    _peopleCountService.nearbyPeopleCount.addListener(_logPeopleCount);
    _peopleCountService.isViewportActive.addListener(_logViewportState);

    // Seed imediato: ValueNotifier não notifica o valor atual ao adicionar listener.
    _updateCachedNearbyUser();
    
    if (kDebugMode) {
      print('[PeopleButton] initState - Estado inicial:');
      print('  - isLoading: ${_peopleCountService.isLoading.value}');
      print('  - isViewportActive: ${_peopleCountService.isViewportActive.value}');
      print('  - nearbyPeopleCount: ${_peopleCountService.nearbyPeopleCount.value}');
      print('  - nearbyPeople.length: ${_peopleCountService.nearbyPeople.value.length}');
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print('[PeopleButton] dispose - Limpando listeners');
    }
    _peopleCountService.nearbyPeople.removeListener(_updateCachedNearbyUser);
    _peopleCountService.isLoading.removeListener(_logLoadingState);
    _peopleCountService.nearbyPeopleCount.removeListener(_logPeopleCount);
    _peopleCountService.isViewportActive.removeListener(_logViewportState);
    _cachedNearbyUser.dispose();
    super.dispose();
  }

  void _updateCachedNearbyUser() {
    final people = _peopleCountService.nearbyPeople.value;
    if (kDebugMode) {
      print('[PeopleButton] _updateCachedNearbyUser - people.length: ${people.length}');
    }
    if (people.isEmpty) return;

    final first = people.first;
    final current = _cachedNearbyUser.value;
    if (current?.userId == first.userId && current?.photoUrl == first.photoUrl) {
      if (kDebugMode) {
        print('[PeopleButton] _updateCachedNearbyUser - Cache já atualizado (userId: ${first.userId})');
      }
      return;
    }

    if (kDebugMode) {
      print('[PeopleButton] _updateCachedNearbyUser - Atualizando cache com userId: ${first.userId}');
    }
    _cachedNearbyUser.value = first;
  }
  
  void _logLoadingState() {
    if (kDebugMode) {
      print('[PeopleButton] isLoading mudou para: ${_peopleCountService.isLoading.value}');
    }
  }
  
  void _logPeopleCount() {
    if (kDebugMode) {
      print('[PeopleButton] nearbyPeopleCount mudou para: ${_peopleCountService.nearbyPeopleCount.value}');
    }
  }
  
  void _logViewportState() {
    if (kDebugMode) {
      print('[PeopleButton] isViewportActive mudou para: ${_peopleCountService.isViewportActive.value}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    final titleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      color: GlimpseColors.primaryColorLight,
    );

    final subtitleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 13.sp,
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
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.sizeOf(context).width > 390;
    final compactButtonSize = isLargeScreen ? math.min(56.0, 56.w) : 56.h;

    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: compactButtonSize,
        height: compactButtonSize,
        decoration: BoxDecoration(
          color: GlimpseColors.lightTextField,
          borderRadius: BorderRadius.circular(100),
        ),
        alignment: Alignment.center,
        child: Icon(
          Iconsax.eye_slash,
          size: 24.sp,
          color: GlimpseColors.primary,
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

  /// Verifica se é VIP antes de abrir a tela
  Future<void> _handleTap(BuildContext context) async {
    // Guarda o status VIP antes de mostrar o dialog
    final wasVipBefore = VipAccessService.isVip;
    
    // checkAccessOrShowDialog verifica Firestore E mostra dialog se necessário
    final hasAccess = await VipAccessService.checkAccessOrShowDialog(
      context,
      source: 'PeopleButton',
    );
    
    if (hasAccess) {
      // Se o usuário acabou de virar VIP (comprou agora), limpa o cache
      // para forçar nova busca com limite VIP (500 em vez de 17)
      if (!wasVipBefore) {
        debugPrint('🎉 [PeopleButton] VIP recém-ativado! Limpando cache para refresh com limite VIP...');
        peopleCountService.clearCache();
        // Força refresh imediato para buscar com novo limite
        await peopleCountService.refreshCurrentBounds();
      }
      onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.sizeOf(context).width > 390;
    final compactButtonSize = isLargeScreen ? math.min(56.0, 56.w) : 56.h;
    final avatarSize = isLargeScreen ? math.min(40.0, 40.w) : 32.w;
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

                const subtitleLineHeight = 18.0;

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
                        onTap: () => _handleTap(context),
                        borderRadius: BorderRadius.circular(100),
                        child: Container(
                          height: compactButtonSize,
                          padding: EdgeInsets.only(left: 6.w, right: 8.w),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (effectiveUser != null)
                                Builder(
                                  builder: (context) {
                                    return Container(
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
                                        size: avatarSize,
                                        enableNavigation: false,
                                      ),
                                    );
                                  },
                                )
                              else if (isLoading)
                                Container(
                                  width: avatarSize,
                                  height: avatarSize,
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
                                SizedBox(
                                  width: avatarSize,
                                  height: avatarSize,
                                ),
                              SizedBox(width: 8.w),
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
                                        dotSize: 5.w,
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
                                size: 20.sp,
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
