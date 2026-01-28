import 'package:partiu/core/utils/app_logger.dart';
import 'package:flutter/material.dart';

/// Enum para cada step do wizard de cadastro
/// NOTA: Removido fluxo bride - apenas vendor
/// OTIMIZADO: Apenas 3 steps essenciais para reduzir friction
enum SignupWizardStep {
  profilePhoto,
  personalInfo,
  gender,
  lookingFor,
  bio,
  instagram,
  interests,
  country,
  origin,
  evaluation,
}

/// ViewModel para o wizard de cadastro
/// 
/// Gerencia apenas o fluxo VENDOR (sem bride)
/// - Steps do fluxo
/// - Progresso
/// - Navegação entre steps
class SignupWizardViewModel extends ChangeNotifier {
  static const String _tag = 'SignupWizardViewModel';
  
  int _currentStepIndex = 0;
  
  // Lista otimizada de steps (apenas essenciais)
  final List<SignupWizardStep> _steps = [
    SignupWizardStep.profilePhoto,
    SignupWizardStep.personalInfo,
    SignupWizardStep.gender,
    SignupWizardStep.lookingFor,
    SignupWizardStep.bio,
    SignupWizardStep.instagram,
    SignupWizardStep.interests,
    SignupWizardStep.country,
    SignupWizardStep.origin,
    SignupWizardStep.evaluation,
  ];
  
  // Getters
  int get currentStepIndex => _currentStepIndex;
  List<SignupWizardStep> get steps => List.unmodifiable(_steps);
  SignupWizardStep get currentStep => _steps[_currentStepIndex];
  int get totalSteps => _steps.length;
  bool get isFirstStep => _currentStepIndex == 0;
  bool get isLastStep => _currentStepIndex >= _steps.length - 1;
  
  /// Calcula o progresso (0.0 a 1.0)
  double get progress => (_currentStepIndex + 1) / _steps.length;
  
  /// Avança para o próximo step
  void nextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      AppLogger.info(
        'Moving to step ${_currentStepIndex + 1}/$_steps.length}: ${currentStep.name}',
        tag: _tag,
      );
      notifyListeners();
    } else {
      AppLogger.warning('Already at last step', tag: _tag);
    }
  }
  
  /// Volta para o step anterior
  void previousStep() {
    if (_currentStepIndex > 0) {
      _currentStepIndex--;
      AppLogger.info(
        'Back to step ${_currentStepIndex + 1}/${_steps.length}: ${currentStep.name}',
        tag: _tag,
      );
      notifyListeners();
    } else {
      AppLogger.warning('Already at first step', tag: _tag);
    }
  }
  
  /// Reseta o wizard para o início
  void reset() {
    _currentStepIndex = 0;
    AppLogger.info('Wizard reset to first step', tag: _tag);
    notifyListeners();
  }
}
