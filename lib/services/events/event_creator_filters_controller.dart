import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/constants/constants.dart';

/// Opções de filtro para eventos baseadas no criador
class EventCreatorFilterOptions {
  final String? creatorGender;
  final String? creatorSexualOrientation;
  final int? creatorMinAge;
  final int? creatorMaxAge;
  final bool? creatorVerified;
  final List<String>? creatorInterests;

  const EventCreatorFilterOptions({
    this.creatorGender,
    this.creatorSexualOrientation,
    this.creatorMinAge,
    this.creatorMaxAge,
    this.creatorVerified,
    this.creatorInterests,
  });

  bool get hasActiveFilters {
    return (creatorGender != null && creatorGender != 'all') ||
        (creatorSexualOrientation != null && creatorSexualOrientation != 'all') ||
        creatorMinAge != null ||
        creatorMaxAge != null ||
        creatorVerified == true ||
        (creatorInterests != null && creatorInterests!.isNotEmpty);
  }
}

/// Controller dos filtros de eventos (por atributos do criador).
/// 
/// Usa a coleção `events_card_preview` que contém dados desnormalizados
/// do criador para permitir filtros eficientes sem N+1.
class EventCreatorFiltersController extends ChangeNotifier {
  static final EventCreatorFiltersController _instance =
      EventCreatorFiltersController._internal();
  factory EventCreatorFiltersController() => _instance;
  EventCreatorFiltersController._internal();

  String? _gender = 'all';
  String? _sexualOrientation = 'all';
  int _minAge = MIN_AGE.toInt();
  int _maxAge = MAX_AGE.toInt();
  bool _isVerified = false;
  List<String> _interests = [];

  bool _isLoading = false;
  bool _filtersEnabled = false;

  bool get isLoading => _isLoading;
  bool get filtersEnabled => _filtersEnabled;
  String? get gender => _gender;
  String? get sexualOrientation => _sexualOrientation;
  int get minAge => _minAge;
  int get maxAge => _maxAge;
  bool get isVerified => _isVerified;
  List<String> get interests => _interests;

  /// Verifica se há filtros ativos (para exibir indicador visual)
  bool get hasActiveFilters {
    if (!_filtersEnabled) return false;
    return (_gender != null && _gender != 'all') ||
        (_sexualOrientation != null && _sexualOrientation != 'all') ||
        _minAge > MIN_AGE.toInt() ||
        _maxAge < MAX_AGE.toInt() ||
        _isVerified ||
        _interests.isNotEmpty;
  }

  /// Retorna as opções de filtro atuais
  EventCreatorFilterOptions get currentFilters {
    if (!_filtersEnabled) {
      return const EventCreatorFilterOptions();
    }
    return EventCreatorFilterOptions(
      creatorGender: _gender != 'all' ? _gender : null,
      creatorSexualOrientation: _sexualOrientation != 'all' ? _sexualOrientation : null,
      creatorMinAge: _minAge > MIN_AGE.toInt() ? _minAge : null,
      creatorMaxAge: _maxAge < MAX_AGE.toInt() ? _maxAge : null,
      creatorVerified: _isVerified ? true : null,
      creatorInterests: _interests.isNotEmpty ? _interests : null,
    );
  }

  /// Carrega filtros salvos do Firestore
  Future<void> loadFromFirestore() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      final data = doc.data()?['eventCreatorFilters'] as Map<String, dynamic>?;

      if (data != null) {
        _filtersEnabled = data['enabled'] as bool? ?? false;
        _gender = data['gender'] as String? ?? 'all';
        _sexualOrientation = data['sexualOrientation'] as String? ?? 'all';
        _minAge = data['minAge'] as int? ?? MIN_AGE.toInt();
        _maxAge = data['maxAge'] as int? ?? MAX_AGE.toInt();
        _isVerified = data['isVerified'] as bool? ?? false;
        _interests = List<String>.from(data['interests'] ?? []);
      }
    } catch (e) {
      debugPrint('❌ EventCreatorFiltersController: erro ao carregar filtro: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // -------------------------------
  //   MÉTODOS DE SET (com notify)
  // -------------------------------

  set filtersEnabled(bool value) {
    _filtersEnabled = value;
    notifyListeners();
  }

  set gender(String? value) {
    _gender = value;
    notifyListeners();
  }

  set sexualOrientation(String? value) {
    _sexualOrientation = value;
    notifyListeners();
  }

  void setAgeRange(int min, int max) {
    _minAge = min;
    _maxAge = max;
    notifyListeners();
  }

  set isVerified(bool value) {
    _isVerified = value;
    notifyListeners();
  }

  set interests(List<String> value) {
    _interests = value;
    notifyListeners();
  }

  /// Reseta todos os filtros para valores padrão
  void resetFilters() {
    _filtersEnabled = false;
    _gender = 'all';
    _sexualOrientation = 'all';
    _minAge = MIN_AGE.toInt();
    _maxAge = MAX_AGE.toInt();
    _isVerified = false;
    _interests = [];
    notifyListeners();
  }

  // -------------------------------
  //          SALVAR
  // -------------------------------
  Future<void> saveToFirestore() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final data = <String, dynamic>{
        'enabled': _filtersEnabled,
        'gender': _gender,
        'sexualOrientation': _sexualOrientation,
        'minAge': _minAge,
        'maxAge': _maxAge,
        'isVerified': _isVerified,
        'interests': _interests,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .set({'eventCreatorFilters': data}, SetOptions(merge: true));

      debugPrint('✅ EventCreatorFiltersController: filtros salvos');
    } catch (e) {
      debugPrint('❌ EventCreatorFiltersController: erro ao salvar filtro: $e');
    }
  }

  /// Aplica filtros em uma lista de eventos localmente
  /// 
  /// Este método é usado para filtrar eventos já carregados sem fazer
  /// queries adicionais ao Firestore.
  List<T> applyFiltersLocally<T>({
    required List<T> events,
    required String? Function(T) getCreatorGender,
    required int? Function(T) getCreatorBirthYear,
    required bool Function(T) getCreatorVerified,
    required List<String> Function(T) getCreatorInterests,
    required String? Function(T) getCreatorSexualOrientation,
  }) {
    if (!_filtersEnabled || !hasActiveFilters) {
      return events;
    }

    final currentYear = DateTime.now().year;

    return events.where((event) {
      // Filtro por gênero
      if (_gender != null && _gender != 'all') {
        final eventGender = getCreatorGender(event);
        if (eventGender != _gender) return false;
      }

      // Filtro por orientação sexual
      if (_sexualOrientation != null && _sexualOrientation != 'all') {
        final eventOrientation = getCreatorSexualOrientation(event);
        if (eventOrientation != _sexualOrientation) return false;
      }

      // Filtro por idade
      final birthYear = getCreatorBirthYear(event);
      if (birthYear != null) {
        final age = currentYear - birthYear;
        if (age < _minAge || age > _maxAge) return false;
      }

      // Filtro por verificado
      if (_isVerified) {
        if (!getCreatorVerified(event)) return false;
      }

      // Filtro por interesses
      if (_interests.isNotEmpty) {
        final eventInterests = getCreatorInterests(event);
        if (!_interests.any((i) => eventInterests.contains(i))) return false;
      }

      return true;
    }).toList();
  }
}
