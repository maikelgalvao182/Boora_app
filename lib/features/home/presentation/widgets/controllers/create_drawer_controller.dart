import 'package:flutter/material.dart';

/// Controller para gerenciar o estado do CreateDrawer
class CreateDrawerController extends ChangeNotifier {
  final TextEditingController textController = TextEditingController();
  
  String _currentEmoji = '🎉';
  bool _isSuggestionMode = false;
  bool _isUpdatingFromSuggestion = false;

  String get currentEmoji => _currentEmoji;
  bool get isSuggestionMode => _isSuggestionMode;
  bool get isUpdatingFromSuggestion => _isUpdatingFromSuggestion;
  bool get canContinue => textController.text.trim().isNotEmpty;

  CreateDrawerController() {
    textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    notifyListeners();
  }

  void setEmoji(String emoji) {
    if (_currentEmoji != emoji) {
      _currentEmoji = emoji;
      notifyListeners();
    }
  }

  void toggleSuggestionMode() {
    _isSuggestionMode = !_isSuggestionMode;
    notifyListeners();
  }

  void setIsUpdatingFromSuggestion(bool value) {
    _isUpdatingFromSuggestion = value;
  }

  void setSuggestion(String text, String emoji) {
    _isUpdatingFromSuggestion = true;
    textController.text = text;
    _currentEmoji = emoji;
    _isSuggestionMode = false;
    notifyListeners();
    _isUpdatingFromSuggestion = false;
  }

  void clear() {
    textController.clear();
    _currentEmoji = '🎉';
    _isSuggestionMode = false;
    _isUpdatingFromSuggestion = false;
    notifyListeners();
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }
}
