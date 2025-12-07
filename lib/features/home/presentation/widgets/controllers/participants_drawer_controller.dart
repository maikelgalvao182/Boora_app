import 'package:flutter/material.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';

/// Controller para gerenciar o estado do ParticipantsDrawer
class ParticipantsDrawerController extends ChangeNotifier {
  double _minAge = MIN_AGE;
  double _maxAge = DEFAULT_MAX_AGE_PARTICIPANTS;
  PrivacyType? _selectedPrivacyType;

  double get minAge => _minAge;
  double get maxAge => _maxAge;
  PrivacyType? get selectedPrivacyType => _selectedPrivacyType;
  bool get canContinue => _selectedPrivacyType != null;

  void setAgeRange(double minAge, double maxAge) {
    _minAge = minAge;
    _maxAge = maxAge;
    notifyListeners();
  }

  void setPrivacyType(PrivacyType? type) {
    _selectedPrivacyType = type;
    notifyListeners();
  }

  /// Retorna os dados para o fluxo
  Map<String, dynamic> getParticipantsData() {
    return {
      'minAge': _minAge.round(),
      'maxAge': _maxAge.round(),
      'privacyType': _selectedPrivacyType,
    };
  }

  void clear() {
    _minAge = MIN_AGE;
    _maxAge = DEFAULT_MAX_AGE_PARTICIPANTS;
    _selectedPrivacyType = null;
    notifyListeners();
  }
}
