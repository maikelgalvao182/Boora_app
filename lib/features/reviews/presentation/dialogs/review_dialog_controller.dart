import 'package:flutter/material.dart';
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/domain/constants/review_criteria.dart';

/// Controller para o ReviewDialog com 3 steps
/// Step 0: Ratings, Step 1: Badges, Step 2: Comentário
class ReviewDialogController extends ChangeNotifier {
  final ReviewRepository _repository = ReviewRepository();
  
  final String eventId;
  final String revieweeId;
  final String reviewerRole;

  ReviewDialogController({
    required this.eventId,
    required this.revieweeId,
    required this.reviewerRole,
  });

  // Step atual (0: Ratings, 1: Badges, 2: Comentário)
  int currentStep = 0;

  // Step 0: Ratings (1-5 estrelas)
  final Map<String, int> ratings = {};

  // Step 1: Badges selecionados
  final List<String> selectedBadges = [];

  // Step 2: Comentário
  final TextEditingController commentController = TextEditingController();

  // Estado
  bool isSubmitting = false;
  String? errorMessage;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  // ==================== STEP 0: RATINGS ====================

  /// Define rating para um critério
  void setRating(String criterion, int value) {
    ratings[criterion] = value;
    errorMessage = null;
    notifyListeners();
  }

  /// Avança para step de badges
  void goToBadgesStep() {
    if (ratings.isEmpty) {
      errorMessage = 'Por favor, avalie pelo menos um critério';
      notifyListeners();
      return;
    }

    errorMessage = null;
    currentStep = 1;
    notifyListeners();
  }

  // ==================== STEP 1: BADGES ====================

  /// Toggle badge (seleciona/deseleciona)
  void toggleBadge(String badgeKey) {
    if (selectedBadges.contains(badgeKey)) {
      selectedBadges.remove(badgeKey);
    } else {
      selectedBadges.add(badgeKey);
    }
    notifyListeners();
  }

  /// Avança para step de comentário
  void goToCommentStep() {
    errorMessage = null;
    currentStep = 2;
    notifyListeners();
  }

  // ==================== STEP 2: COMENTÁRIO ====================

  /// Submete review (com ou sem comentário)
  Future<bool> submitReview() async {
    final comment = commentController.text.trim();

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _repository.createReview(
        eventId: eventId,
        revieweeId: revieweeId,
        reviewerRole: reviewerRole,
        criteriaRatings: ratings,
        badges: selectedBadges,
        comment: comment.isEmpty ? null : comment,
      );

      isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _getErrorMessage(e);
      isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  /// Pula comentário e submete direto
  Future<bool> skipCommentAndSubmit() async {
    return submitReview();
  }

  // ==================== NAVEGAÇÃO ====================

  /// Volta para step anterior
  void previousStep() {
    if (currentStep > 0) {
      currentStep--;
      errorMessage = null;
      notifyListeners();
    }
  }

  /// Verifica se pode voltar
  bool get canGoBack => currentStep > 0;

  // ==================== HELPERS ====================

  /// Lista de critérios para exibir
  List<Map<String, String>> get criteriaList => ReviewCriteria.all;

  /// Progresso atual (0.0 a 1.0)
  double get progress => (currentStep + 1) / 3;

  /// Label do step atual
  String get currentStepLabel {
    switch (currentStep) {
      case 0:
        return 'Avalie os critérios';
      case 1:
        return 'Escolha badges (opcional)';
      case 2:
        return 'Deixe um comentário (opcional)';
      default:
        return '';
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('já avaliou')) {
      return 'Você já avaliou esta pessoa neste evento';
    } else if (errorString.contains('autenticado')) {
      return 'Você precisa estar logado para avaliar';
    } else if (errorString.contains('network')) {
      return 'Erro de conexão. Verifique sua internet';
    } else {
      return 'Erro ao enviar avaliação. Tente novamente';
    }
  }
}
