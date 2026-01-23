import 'package:flutter/material.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Widget reativo que exibe a localização do usuário (cidade, estado)
/// 
/// Usa UserStore para reatividade granular - atualiza instantaneamente
/// quando a localização muda no Firestore.
class ReactiveUserLocation extends StatelessWidget {
  const ReactiveUserLocation({
    super.key,
    required this.userId,
    this.style,
    this.fallbackText = 'Location not defined',
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
  });

  final String userId;
  final TextStyle? style;
  final String fallbackText;
  final TextAlign textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return Text(
        fallbackText,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final cityNotifier = UserStore.instance.getCityNotifier(userId);
    final stateNotifier = UserStore.instance.getStateNotifier(userId);

    return ValueListenableBuilder<String?>(
      valueListenable: cityNotifier,
      builder: (context, city, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: stateNotifier,
          builder: (context, state, _) {
            final locality = city ?? '';
            final stateStr = state ?? '';
            
            final location = locality.isNotEmpty && stateStr.isNotEmpty
                ? '$locality, $stateStr'
                : locality.isNotEmpty
                    ? locality
                    : stateStr.isNotEmpty
                        ? stateStr
                        : fallbackText;

            return Text(
              location,
              style: style,
              textAlign: textAlign,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            );
          },
        );
      },
    );
  }
}
