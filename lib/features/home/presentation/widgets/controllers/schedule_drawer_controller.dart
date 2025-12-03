import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';

/// Controller para gerenciar o estado do ScheduleDrawer
class ScheduleDrawerController extends ChangeNotifier {
  DateTime _selectedDate = DateTime.now();
  TimeType? _selectedTimeType;
  DateTime _selectedTime = DateTime.now();

  DateTime get selectedDate => _selectedDate;
  TimeType? get selectedTimeType => _selectedTimeType;
  DateTime get selectedTime => _selectedTime;
  bool get canContinue => _selectedTimeType != null;

  void setDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  void setTimeType(TimeType? type) {
    _selectedTimeType = type;
    notifyListeners();
  }

  void setTime(DateTime time) {
    _selectedTime = time;
    notifyListeners();
  }

  /// Retorna os dados para o fluxo
  Map<String, dynamic> getScheduleData() {
    return {
      'date': _selectedDate,
      'timeType': _selectedTimeType,
      if (_selectedTimeType == TimeType.specific) 'time': _selectedTime,
    };
  }

  void clear() {
    _selectedDate = DateTime.now();
    _selectedTimeType = null;
    _selectedTime = DateTime.now();
    notifyListeners();
  }
}
