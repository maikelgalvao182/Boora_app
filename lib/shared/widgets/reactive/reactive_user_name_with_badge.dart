import 'package:flutter/material.dart';
import 'package:partiu/shared/stores/user_store.dart';

/// Widget reativo que exibe o nome do usuário com badge de verificado
/// 
/// Usa UserStore para reatividade granular (nome + verificado)
class ReactiveUserNameWithBadge extends StatelessWidget {
  const ReactiveUserNameWithBadge({
    super.key,
    required this.userId,
    this.style,
    this.iconSize = 13.0,
    this.spacing = 4.0,
    this.textAlign = TextAlign.start,
  });

  final String userId;
  final TextStyle? style;
  final double iconSize;
  final double spacing;
  final TextAlign textAlign;

  String _buildDisplayName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Usuário';

    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Usuário';

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
    if (userId.isEmpty) {
      return const SizedBox.shrink();
    }

    final nameNotifier = UserStore.instance.getNameNotifier(userId);
    final verifiedNotifier = UserStore.instance.getVerifiedNotifier(userId);

    return ValueListenableBuilder<String?>(
      valueListenable: nameNotifier,
      builder: (context, name, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: verifiedNotifier,
          builder: (context, isVerified, _) {
            final displayName = _buildDisplayName(name ?? '');

            return Row(
              mainAxisAlignment: textAlign == TextAlign.center 
                  ? MainAxisAlignment.center 
                  : MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    style: style ?? TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white 
                          : Colors.black,
                    ),
                    textAlign: textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isVerified) ...[
                  SizedBox(width: spacing),
                  Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.verified,
                      size: iconSize,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}