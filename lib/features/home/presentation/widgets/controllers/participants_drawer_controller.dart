import 'package:flutter/material.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/features/home/presentation/widgets/participants/gender_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';

/// Controller para gerenciar o estado do ParticipantsDrawer
class ParticipantsDrawerController extends ChangeNotifier {
  double _minAge = MIN_AGE;
  double _maxAge = DEFAULT_MAX_AGE_PARTICIPANTS;
  PrivacyType? _selectedPrivacyType;
  // GenderType removed - controlled by PrivacyType
  String _selectedGender = GENDER_MAN;

  double get minAge => _minAge;
  double get maxAge => _maxAge;
  PrivacyType? get selectedPrivacyType => _selectedPrivacyType;
  String get selectedGender => _selectedGender;
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

  void setGender(String gender) {
    _selectedGender = gender;
    notifyListeners();
  }

  /// Retorna os dados para o fluxo
  Map<String, dynamic> getParticipantsData() {
    // Se o tipo selecionado for Gênero Específico, retorna o gênero escolhido
    // Caso contrário (Open ou Private), considera "All" para o gênero
    final gender = _selectedPrivacyType == PrivacyType.specificGender 
        ? _selectedGender 
        : GENDER_ALL;

    // Se o tipo for specificGender, mapeamos para "open" no backend 
    // (mas com o campo gender setado). 
    // Ou mantemos o privacyType como 'open' e o gender faz o filtro.
    // O backend espera: privacyType (string) + gender (string)
    
    // Mapeamento de PrivacyType UI -> String Backend
    String privacyTypeString = 'open';
    if (_selectedPrivacyType == PrivacyType.private) {
      privacyTypeString = 'private';
    } 
    // Se for specificGender, tratamos como 'open' (público mas filtrado) 
    // ou mantemos logicamente consistente.
    
    return {
      'minAge': _minAge.round(),
      'maxAge': _maxAge.round(),
      'privacyType': _selectedPrivacyType, // Passamos o enum para o coordinator lidar
      'gender': gender,
    };
  }

  void clear() {
    _minAge = MIN_AGE;
    _maxAge = DEFAULT_MAX_AGE_PARTICIPANTS;
    _selectedPrivacyType = null;
    _selectedGender = GENDER_MAN;
    notifyListeners();
  }
}
