import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/services/location/location_stream_controller.dart';

/// Controller para gerenciar o raio de busca com debounce,
/// agora SEM sobrescrever outros filtros dentro de advancedSettings.
class RadiusController extends ChangeNotifier {
  double _radiusKm = DEFAULT_RADIUS_KM;

  static const double minRadius = MIN_RADIUS_KM;
  static final double maxRadius = ENABLE_RADIUS_LIMIT ? MAX_RADIUS_KM : MAX_RADIUS_KM_EXTENDED;

  static const Duration debounceDuration = Duration(milliseconds: 500);

  Timer? _debounceTimer;
  bool _isUpdating = false;

  final _radiusStreamController = StreamController<double>.broadcast();

  RadiusController();

  double get radiusKm => _radiusKm;
  bool get isUpdating => _isUpdating;

  Stream<double> get radiusStream => _radiusStreamController.stream;

  /// Carrega o valor do Firestore — sempre usado externamente,
  /// e NÃO no construtor (para evitar race condition).
  Future<void> loadFromFirestore() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      if (!userDoc.exists) return;

      final data = userDoc.data();
      if (data == null) return;

      final settings = data['advancedSettings'] as Map<String, dynamic>?;

      final savedRadius = settings?['radiusKm'] as num?;
      if (savedRadius != null) {
        // Garante que o valor carregado respeite os limites atuais
        _radiusKm = savedRadius.toDouble().clamp(minRadius, maxRadius);
        notifyListeners();
        _radiusStreamController.add(_radiusKm);
      }
    } catch (e) {
      debugPrint('❌ RadiusController: Erro ao carregar raio: $e');
    }
  }

  /// Atualiza o raio com debounce
  void updateRadius(double newRadius) {
    if (newRadius < minRadius || newRadius > maxRadius) return;

    _radiusKm = newRadius;
    notifyListeners();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () => _saveToFirestore());
  }

  /// Salva apenas radiusKm usando MERGE
  Future<void> _saveToFirestore() async {
    if (_isUpdating) return;

    _isUpdating = true;
    notifyListeners();

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final userRef = FirebaseFirestore.instance.collection('Users').doc(userId);

      // Usar update() com dot notation para atualizar apenas radiusKm
      // SEM substituir outros campos do map advancedSettings
      await userRef.update({
        'advancedSettings.radiusKm': _radiusKm,
        'advancedSettings.radiusUpdatedAt': FieldValue.serverTimestamp(),
      });

      _radiusStreamController.add(_radiusKm);
      LocationStreamController().emitRadiusChange(_radiusKm);

    } catch (e) {
      debugPrint('❌ RadiusController: Erro ao salvar raio: $e');
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<void> saveImmediately() async {
    _debounceTimer?.cancel();
    await _saveToFirestore();
  }

  /// Reseta o raio para o valor padrão
  void resetToDefault() {
    _radiusKm = DEFAULT_RADIUS_KM;
    notifyListeners();
    _radiusStreamController.add(_radiusKm);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _radiusStreamController.close();
    super.dispose();
  }
}
