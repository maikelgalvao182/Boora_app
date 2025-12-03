import 'package:flutter/material.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';

/// Controller para gerenciar o estado do ParticipantsDrawer
class ParticipantsDrawerController extends ChangeNotifier {
  double _minAge = 18;
  double _maxAge = 80;
  PrivacyType? _selectedPrivacyType;
  bool _isPeoplePickerExpanded = false;
  int _maxParticipants = 0; // 0 = Aberto, 1-20 = específico

  double get minAge => _minAge;
  double get maxAge => _maxAge;
  PrivacyType? get selectedPrivacyType => _selectedPrivacyType;
  bool get isPeoplePickerExpanded => _isPeoplePickerExpanded;
  int get maxParticipants => _maxParticipants;
  bool get canContinue => _selectedPrivacyType != null;

  void setAgeRange(double minAge, double maxAge) {
    _minAge = minAge;
    _maxAge = maxAge;
    notifyListeners();
  }

  void setPrivacyType(PrivacyType? type) {
    _selectedPrivacyType = type;
    // Auto-expandir people picker quando Aberto for selecionado
    if (type == PrivacyType.open) {
      _isPeoplePickerExpanded = true;
    } else {
      _isPeoplePickerExpanded = false;
      _maxParticipants = 0; // Resetar para Aberto
    }
    notifyListeners();
  }

  void togglePeoplePickerExpanded() {
    _isPeoplePickerExpanded = !_isPeoplePickerExpanded;
    notifyListeners();
  }

  void setMaxParticipants(int count) {
    _maxParticipants = count;
    notifyListeners();
  }

  /// Retorna os dados para o fluxo
  Map<String, dynamic> getParticipantsData() {
    return {
      'minAge': _minAge.round(),
      'maxAge': _maxAge.round(),
      'privacyType': _selectedPrivacyType,
      'maxParticipants': _maxParticipants,
    };
  }

  void clear() {
    _minAge = 18;
    _maxAge = 80;
    _selectedPrivacyType = null;
    _isPeoplePickerExpanded = false;
    _maxParticipants = 0;
    notifyListeners();
  }
}
