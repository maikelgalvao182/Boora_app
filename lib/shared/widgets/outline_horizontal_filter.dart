import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/text_styles.dart';

class OutlineHorizontalFilter extends StatelessWidget {
  const OutlineHorizontalFilter({
    super.key,
    required this.values,
    this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();

    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    final fontSize = (isCompactScreen ? 12 : 13).sp;

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: values.length,
      separatorBuilder: (_, __) => SizedBox(width: 4.w),
      itemBuilder: (_, i) {
        final item = values[i];
        final isSelected = item == selected;

        return GestureDetector(
          onTap: () => onSelected(isSelected ? null : item),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 4.w),
            padding: EdgeInsets.symmetric(horizontal: 18.w),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100.r),
              border: Border.all(
                color: isSelected ? GlimpseColors.primaryColorLight : GlimpseColors.borderColorLight,
                width: 1.5.w,
              ),
              color: isSelected ? GlimpseColors.lightTextField : Colors.transparent,
            ),
            child: Text(
              item,
              style: isSelected 
                  ? TextStyles.filterSelected.copyWith(
                      color: GlimpseColors.primaryColorLight,
                      fontSize: fontSize,
                      height: 1.2,
                    )
                  : TextStyles.filterDefault.copyWith(
                      fontSize: fontSize,
                      height: 1.2,
                    ),
            ),
          ),
        );
      },
    );
  }
}
