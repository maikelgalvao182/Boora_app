import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_segmented_tabs.dart';

class EventPhotoFeedTabs extends StatelessWidget {
  const EventPhotoFeedTabs({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return GlimpseSegmentedTabs(
      labels: [
        i18n.translate('event_photo_tab_global'),
        i18n.translate('event_photo_tab_following'),
        i18n.translate('event_photo_tab_my_posts'),
      ],
      currentIndex: currentIndex,
      onChanged: onChanged,
    );
  }
}
