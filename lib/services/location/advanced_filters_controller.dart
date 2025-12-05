import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/core/constants/constants.dart';

/// Controller dos filtros avançados.
/// Agora SEM sobrescrever radiusKm, SEM race condition e SEM perder dados.
class AdvancedFiltersController extends ChangeNotifier {
  String? _gender = 'all';
  int _minAge = MIN_AGE.toInt();
  int _maxAge = MAX_AGE.toInt();
  bool _isVerified = false;
  List<String> _interests = [];

  bool _isLoading = false;

  bool get isLoading => _isLoading;
  String? get gender => _gender;
  int get minAge => _minAge;
  int get maxAge => _maxAge;
  bool get isVerified => _isVerified;
  List<String> get interests => _interests;

  AdvancedFiltersController();

  /// Carregar explicitamente (NÃO no construtor)
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

      final data = doc.data()?['advancedSettings'] as Map<String, dynamic>?;

      if (data != null) {
        _gender = data['gender'] as String? ?? 'all';
        _minAge = data['minAge'] as int? ?? MIN_AGE.toInt();
        _maxAge = data['maxAge'] as int? ?? MAX_AGE.toInt();
        _isVerified = data['isVerified'] as bool? ?? false;
        _interests = List<String>.from(data['interests'] ?? []);
      }

    } catch (e) {
      debugPrint('❌ AdvancedFiltersController: erro ao carregar filtro: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // -------------------------------
  //   MÉTODOS DE SET (com notify)
  // -------------------------------

  set gender(String? value) {
    debugPrint('⚠️ AdvancedFiltersController.gender SETTER chamado: $_gender -> $value');
    _gender = value;
    notifyListeners();
  }

  void setAgeRange(int min, int max) {
    debugPrint('⚠️ AdvancedFiltersController.setAgeRange CHAMADO: $_minAge-$_maxAge -> $min-$max');
    _minAge = min;
    _maxAge = max;
    notifyListeners();
  }

  set isVerified(bool value) {
    debugPrint('⚠️ AdvancedFiltersController.isVerified SETTER chamado: $_isVerified -> $value');
    _isVerified = value;
    notifyListeners();
  }

  set interests(List<String> value) {
    debugPrint('⚠️ AdvancedFiltersController.interests SETTER chamado: $_interests -> $value');
    _interests = value;
    notifyListeners();
  }

  // -------------------------------
  //   SALVAR (SEM SOBRESCREVER)
  // -------------------------------
  Future<void> saveToFirestore() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        debugPrint('❌ AdvancedFiltersController.saveToFirestore: userId é null');
        return;
      }

      debugPrint('💾 AdvancedFiltersController.saveToFirestore INICIADO');
      debugPrint('   - userId: $userId');
      debugPrint('   - gender: $_gender (${_gender.runtimeType})');
      debugPrint('   - minAge: $_minAge (${_minAge.runtimeType})');
      debugPrint('   - maxAge: $_maxAge (${_maxAge.runtimeType})');
      debugPrint('   - isVerified: $_isVerified (${_isVerified.runtimeType})');
      debugPrint('   - interests: $_interests (${_interests.runtimeType})');

      final userRef = FirebaseFirestore.instance.collection('Users').doc(userId);

      /// ⚠ IMPORTANTE ⚠  
      /// Usando update() com dot notation para atualizar apenas os campos necessários
      /// SEM substituir radiusKm ou outros campos do map advancedSettings
      
      final updateData = {
        'advancedSettings.gender': _gender,
        'advancedSettings.minAge': _minAge,
        'advancedSettings.maxAge': _maxAge,
        'advancedSettings.isVerified': _isVerified,
        'advancedSettings.interests': _interests,
        'advancedSettings.updatedAt': FieldValue.serverTimestamp(),
      };
      
      debugPrint('📦 Dados a serem enviados para update(): $updateData');
      
      await userRef.update(updateData);
      
      debugPrint('✅ AdvancedFiltersController.saveToFirestore: update() concluído');
      
      // Verificar o que foi realmente salvo
      final verifyDoc = await userRef.get();
      final savedSettings = verifyDoc.data()?['advancedSettings'];
      debugPrint('📡 Firebase retornou advancedSettings: $savedSettings');
      
    } catch (e, stackTrace) {
      debugPrint('❌ AdvancedFiltersController.saveToFirestore: ERRO: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void reset() {
    _gender = 'all';
    _minAge = MIN_AGE.toInt();
    _maxAge = MAX_AGE.toInt();
    _isVerified = false;
    _interests = [];
    notifyListeners();
  }

  /// Adicionar um interesse e salvar imediatamente no Firestore
  Future<void> addInterest(String interest) async {
    if (!_interests.contains(interest)) {
      _interests.add(interest);
      notifyListeners();
      
      try {
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId == null) return;

        await FirebaseFirestore.instance
            .collection('Users')
            .doc(userId)
            .update({
          'advancedSettings.interests': _interests,
          'advancedSettings.updatedAt': FieldValue.serverTimestamp(),
        });
        
        debugPrint('✅ Interest "$interest" adicionado ao Firestore');
      } catch (e) {
        debugPrint('❌ Erro ao adicionar interest: $e');
      }
    }
  }

  /// Remover um interesse e salvar imediatamente no Firestore
  Future<void> removeInterest(String interest) async {
    if (_interests.contains(interest)) {
      _interests.remove(interest);
      notifyListeners();
      
      try {
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId == null) return;

        await FirebaseFirestore.instance
            .collection('Users')
            .doc(userId)
            .update({
          'advancedSettings.interests': _interests,
          'advancedSettings.updatedAt': FieldValue.serverTimestamp(),
        });
        
        debugPrint('✅ Interest "$interest" removido do Firestore');
      } catch (e) {
        debugPrint('❌ Erro ao remover interest: $e');
      }
    }
  }

  /// Limpar todos os filtros e remover do Firestore
  Future<void> clearAllFilters() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        debugPrint('❌ clearAllFilters: userId é null');
        return;
      }

      debugPrint('🧹 Limpando todos os filtros...');

      // Resetar valores locais
      _gender = 'all';
      _minAge = MIN_AGE.toInt();
      _maxAge = MAX_AGE.toInt();
      _isVerified = false;
      _interests = [];
      notifyListeners();

      // Remover do Firestore (exceto radiusKm e radiusUpdatedAt)
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .update({
        'advancedSettings.gender': FieldValue.delete(),
        'advancedSettings.minAge': FieldValue.delete(),
        'advancedSettings.maxAge': FieldValue.delete(),
        'advancedSettings.isVerified': FieldValue.delete(),
        'advancedSettings.interests': FieldValue.delete(),
        'advancedSettings.updatedAt': FieldValue.delete(),
      });

      debugPrint('✅ Todos os filtros foram removidos do Firestore');
    } catch (e) {
      debugPrint('❌ Erro ao limpar filtros: $e');
    }
  }
}
