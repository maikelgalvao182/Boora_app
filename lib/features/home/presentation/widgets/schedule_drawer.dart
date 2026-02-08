import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/widgets/controllers/schedule_drawer_controller.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/horizontal_week_calendar.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_picker_widget.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/animated_expandable.dart';
import 'package:partiu/shared/widgets/navigation_buttons.dart';

/// Bottom sheet para seleção de data e horário da atividade
class ScheduleDrawer extends StatefulWidget {
  const ScheduleDrawer({
    super.key, 
    this.coordinator,
    this.initialDate,
    this.initialTimeType,
    this.initialTime,
    this.editMode = false,
  });

  final CreateFlowCoordinator? coordinator;
  final DateTime? initialDate;
  final TimeType? initialTimeType;
  final DateTime? initialTime;
  final bool editMode;

  @override
  State<ScheduleDrawer> createState() => _ScheduleDrawerState();
}

class _ScheduleDrawerState extends State<ScheduleDrawer> {
  late final ScheduleDrawerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScheduleDrawerController();
    
    // Preencher com valores do coordinator (se existirem) ou valores iniciais
    final savedDate = widget.initialDate ?? widget.coordinator?.draft.selectedDate;
    final savedTimeType = widget.initialTimeType ?? widget.coordinator?.draft.timeType;
    final savedTime = widget.initialTime ?? widget.coordinator?.draft.selectedTime;
    
    if (savedDate != null) {
      _controller.setDate(savedDate);
    }
    if (savedTimeType != null) {
      _controller.setTimeType(savedTimeType);
    }
    if (savedTime != null) {
      _controller.setTime(savedTime);
    }
    
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleContinue() async {
    if (!_controller.canContinue) return;

    // Salvar dados no coordinator
    if (widget.coordinator != null) {
      widget.coordinator!.setSchedule(
        date: _controller.selectedDate,
        timeType: _controller.selectedTimeType!,
        time: _controller.selectedTimeType == TimeType.specific
            ? _controller.selectedTime
            : null,
      );
    }

    // Retornar resultado (próximo passo é LocationPicker)
    if (mounted) {
      Navigator.of(context).pop(_controller.getScheduleData());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(24.r),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle e header
              Padding(
                padding: EdgeInsets.only(
                  top: 12.h,
                  left: 20.w,
                  right: 20.w,
                ),
                child: Column(
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: GlimpseColors.borderColorLight,
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // Header: Título + Close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Título alinhado à esquerda
                        Text(
                          AppLocalizations.of(context).translate('when_activity_title'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w800,
                            color: GlimpseColors.primaryColorLight,
                          ),
                        ),

                        // Botão fechar
                        GlimpseCloseButton(
                          size: 32.w,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            SizedBox(height: 24.h),

              // Calendário horizontal (7 dias)
              HorizontalWeekCalendar(
                selectedDate: _controller.selectedDate,
                onDateSelected: (date) {
                  _controller.setDate(date);
                },
              ),

              SizedBox(height: 24.h),

              // Cards de seleção de horário
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: TimeTypeSelector(
                  selectedType: _controller.selectedTimeType,
                  onTypeSelected: (type) {
                    _controller.setTimeType(type);
                  },
                ),
              ),

              // Hour Picker (apenas quando específico está selecionado)
              AnimatedExpandable(
                isExpanded: _controller.selectedTimeType == TimeType.specific,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 16.h),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w),
                      child: TimePickerWidget(
                        selectedTime: _controller.selectedTime,
                        onTimeChanged: (DateTime newTime) {
                          _controller.setTime(newTime);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24.h),

              // Botões de navegação
              NavigationButtons(
                onBack: () => Navigator.of(context).pop(),
                onContinue: _handleContinue,
                canContinue: _controller.canContinue,
              ),

              // Padding bottom para safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16.h),
            ],
          ),
        ),
      ),
    );
  }
}
