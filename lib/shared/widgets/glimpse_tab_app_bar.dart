import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';

/// AppBar reutilizável para as tabs principais do app
/// Usado em: Profile, Conversations, Ranking, Matches
class GlimpseTabAppBar extends StatelessWidget {
  const GlimpseTabAppBar({
    required this.title,
    super.key,
    this.actions,
    this.leading,
    this.centerTitle = false,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    if (centerTitle) {
      // Usa Stack para centralizar o título ignorando leading/actions
      return Padding(
        padding: EdgeInsets.only(left: 20.w, right: 20.w, top: 8.h),
        child: SizedBox(
          height: 40.h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Título centralizado absolutamente
              Center(
                child: Text(
                  title,
                  style: GlimpseStyles.messagesTitleStyle().copyWith(
                    color: GlimpseColors.primaryColorLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Leading à esquerda
              if (leading != null)
                Positioned(
                  left: 0,
                  child: leading!,
                ),
              // Actions à direita
              if (actions != null)
                Positioned(
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions!,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Layout padrão com título à esquerda
    return Padding(
      padding: EdgeInsets.only(left: 20.w, right: 20.w, top: 8.h),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: 12.w),
          ],
          Expanded(
            child: Text(
              title,
              style: GlimpseStyles.messagesTitleStyle().copyWith(
                color: GlimpseColors.primaryColorLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// Botão de ação otimizado para usar no AppBar
class GlimpseTabActionButton extends StatelessWidget {
  const GlimpseTabActionButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28.w,
      height: 28.h,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          icon,
          size: 24.sp,
          color: GlimpseColors.primaryColorLight,
        ),
        tooltip: tooltip,
        onPressed: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
      ),
    );
  }
}
