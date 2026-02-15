import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/AnimatedSlideIn.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Overlay que promove evento(s) de usuários VIP para TODOS verem.
///
/// Regra de negócio:
/// - O overlay aparece para TODOS os usuários (VIP ou não)
/// - Mostra apenas eventos criados por usuários que têm user_is_vip=true
/// - Filtra por eventos dentro do viewport visível
///
/// Contrato:
/// - inputs: [events] (dataset atual), [visibleBounds] (frame atual)
/// - output: widget que renderiza 0..N cards (apenas eventos de criadores VIP)
/// - interaction: [onEventTap] chamado ao tocar no card (abre EventCard)
class VipEventPromoOverlay extends StatefulWidget {
  const VipEventPromoOverlay({
    required this.events,
    required this.visibleBounds,
    required this.onEventTap,
    super.key,
  });

  final List<EventModel> events;
  final LatLngBounds? visibleBounds;
  final ValueChanged<EventModel> onEventTap;

  @override
  State<VipEventPromoOverlay> createState() => _VipEventPromoOverlayState();
}

class _VipEventPromoOverlayState extends State<VipEventPromoOverlay> {
  // Cache dos notifiers VIP para cada criador
  final Map<String, ValueNotifier<bool>> _vipNotifiers = {};

  @override
  void dispose() {
    // Não dispõe os notifiers pois são gerenciados pelo UserStore
    _vipNotifiers.clear();
    super.dispose();
  }

  ValueNotifier<bool> _getVipNotifier(String userId) {
    return _vipNotifiers.putIfAbsent(
      userId,
      () => UserStore.instance.getVipNotifier(userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = widget.visibleBounds;
    if (bounds == null) {
      return const SizedBox.shrink();
    }

    // Primeiro, filtra eventos dentro do viewport
    final inViewport = widget.events
        .where((e) => _contains(bounds, e.lat, e.lng))
        .toList(growable: false);

    if (inViewport.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isLargeScreen = MediaQuery.sizeOf(context).width > 390;
    final overlayHeight = isLargeScreen ? math.min(46.0, 46.h) : 58.h;

    // Usa um builder que escuta mudanças nos notifiers VIP
    return _VipEventsBuilder(
      events: inViewport,
      getVipNotifier: _getVipNotifier,
      builder: (context, vipEvents) {
        if (vipEvents.isEmpty) {
          return const SizedBox.shrink();
        }

        // Gera uma key baseada nos IDs dos eventos VIP para animar mudanças
        final eventsKey = vipEvents.map((e) => e.id).join('_');

        return AnimatedSlideIn(
          key: ValueKey('vip_overlay_$eventsKey'),
          child: SizedBox(
            height: overlayHeight, // card compacto + espaço para sombra
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: vipEvents.length,
              padding: EdgeInsets.only(right: 8.w),
              itemBuilder: (context, index) {
                final event = vipEvents[index];
                return Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: _PromoCard(
                    event: event,
                    backgroundColor: MarkerColorHelper.getColorForId(event.id),
                    textTheme: theme.textTheme,
                    onTap: () => widget.onEventTap(event),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  bool _contains(LatLngBounds bounds, double lat, double lng) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;

    final minLat = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
    final maxLat = sw.latitude < ne.latitude ? ne.latitude : sw.latitude;
    final withinLat = lat >= minLat && lat <= maxLat;

    final swLng = sw.longitude;
    final neLng = ne.longitude;
    final withinLng = swLng <= neLng ? (lng >= swLng && lng <= neLng) : (lng >= swLng || lng <= neLng);

    return withinLat && withinLng;
  }
}

/// Widget builder que filtra eventos por criadores VIP
class _VipEventsBuilder extends StatefulWidget {
  const _VipEventsBuilder({
    required this.events,
    required this.getVipNotifier,
    required this.builder,
  });

  final List<EventModel> events;
  final ValueNotifier<bool> Function(String userId) getVipNotifier;
  final Widget Function(BuildContext context, List<EventModel> vipEvents) builder;

  @override
  State<_VipEventsBuilder> createState() => _VipEventsBuilderState();
}

class _VipEventsBuilderState extends State<_VipEventsBuilder> {
  final List<VoidCallback> _listeners = [];

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  @override
  void didUpdateWidget(covariant _VipEventsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-setup listeners se a lista de eventos mudou
    _removeListeners();
    _setupListeners();
  }

  @override
  void dispose() {
    _removeListeners();
    super.dispose();
  }

  void _setupListeners() {
    // Escuta mudanças no status VIP de cada criador único
    final creatorIds = widget.events.map((e) => e.createdBy).toSet();
    for (final creatorId in creatorIds) {
      final notifier = widget.getVipNotifier(creatorId);
      void listener() {
        if (mounted) setState(() {});
      }
      notifier.addListener(listener);
      _listeners.add(() => notifier.removeListener(listener));
    }
  }

  void _removeListeners() {
    for (final removeListener in _listeners) {
      removeListener();
    }
    _listeners.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Filtra apenas eventos cujo criador é VIP
    final vipEvents = widget.events.where((event) {
      final notifier = widget.getVipNotifier(event.createdBy);
      return notifier.value;
    }).toList(growable: false);

    return widget.builder(context, vipEvents);
  }
}

class _PromoCard extends StatefulWidget {
  const _PromoCard({
    required this.event,
    required this.backgroundColor,
    required this.textTheme,
    required this.onTap,
  });

  final EventModel event;
  final Color backgroundColor;
  final TextTheme textTheme;
  final VoidCallback onTap;

  @override
  State<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<_PromoCard> {
  /// Formata nome igual ao ReactiveUserNameWithBadge (primeiro nome + inicial do sobrenome)
  String _buildDisplayName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Alguém';

    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Alguém';

    final first = parts.first;
    if (parts.length == 1) {
      return first.length > 15 ? first.substring(0, 15) : first;
    }

    final lastInitial = parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
    final safeFirst = first.length > 15 ? first.substring(0, 15) : first;
    return lastInitial.isEmpty ? safeFirst : '$safeFirst $lastInitial.';
  }

  @override
  Widget build(BuildContext context) {
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    final isLargeScreen = MediaQuery.sizeOf(context).width > 390;
    final avatarAndEmojiSize = math.min(40.0, 40.w);
    final avatarAndEmojiBorderWidth = math.min(4.0, 4.w);
    final promoCardHeight = isLargeScreen ? math.min(40.0, 40.h) : 48.h;
    final avatarInnerSize = avatarAndEmojiSize - (avatarAndEmojiBorderWidth * 2);

    final rawActivityName = widget.event.title.trim().isEmpty 
        ? 'um rolê' 
        : widget.event.title.trim();
    final activityName = rawActivityName.length > 17
        ? '${rawActivityName.substring(0, 17)}...'
        : rawActivityName;

    // Tipografia idêntica ao PeopleButton (GoogleFonts Plus Jakarta Sans) - cores pretas
    final titleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: (isCompactScreen ? 13 : 14).sp,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    );

    final subtitleStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: (isCompactScreen ? 11 : 12).sp,
      fontWeight: FontWeight.w600,
      color: Colors.black54,
    );

    // Usa UserStore para reatividade (igual user_card.dart)
    final nameNotifier = UserStore.instance.getNameNotifier(widget.event.createdBy);

    return ValueListenableBuilder<String?>(
      valueListenable: nameNotifier,
      builder: (context, name, _) {
        final displayName = _buildDisplayName(name ?? '');

        return Material(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(100.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(100.r),
            onTap: widget.onTap,
            child: Container(
              height: promoCardHeight,
              padding: EdgeInsets.only(left: 4.w, right: 10.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(100.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar (emoji removido)
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: Container(
                      width: avatarAndEmojiSize,
                      height: avatarAndEmojiSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: avatarAndEmojiBorderWidth,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: StableAvatar(
                        userId: widget.event.createdBy,
                        photoUrl: '',
                        size: avatarInnerSize,
                        enableNavigation: false,
                      ),
                    ),
                  ),
                  // 2 linhas: "nome quer" / atividade
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                          Text(
                            'quer $activityName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: subtitleStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
