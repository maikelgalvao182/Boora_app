import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

/// Widget de seleção de horário usando CupertinoDatePicker
class TimePickerWidget extends StatelessWidget {
  const TimePickerWidget({
    required this.selectedTime,
    required this.onTimeChanged,
    super.key,
  });

  final DateTime selectedTime;
  final ValueChanged<DateTime> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CupertinoTheme(
        data: const CupertinoThemeData(
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: GlimpseColors.primaryColorLight,
            ),
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: selectedTime,
          use24hFormat: true,
          onDateTimeChanged: onTimeChanged,
        ),
      ),
    );
  }
}
