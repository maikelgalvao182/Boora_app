import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controller para gerenciar o raio de busca com debounce
/// 
/// Responsabilidades:
/// - Controlar valor do raio
/// - Debounce para evitar queries excessivas
/// - Persistir no Firestore
/// - Notificar listeners
class RadiusController extends ChangeNotifier {
  /// Valor atual do raio em km
  double _radiusKm = 25.0;

  /// Valor mínimo do raio
  static const double minRadius = 1.0;

  /// Valor máximo do raio
  static const double maxRadius = 100.0;

  /// Duração do debounce (500ms)
  static const Duration debounceDuration = Duration(milliseconds: 500);

  /// Timer para debounce
  Timer? _debounceTimer;

  /// Flag de loading
  bool _isUpdating = false;

  /// Stream controller para broadcasts
  final _radiusStreamController = StreamController<double>.broadcast();

  RadiusController() {
    _loadFromFirestore();
  }

  /// Getter do raio atual
  double get radiusKm => _radiusKm;

  /// Getter de loading
  bool get isUpdating => _isUpdating;

  /// Stream de mudanças de raio
  Stream<double> get radiusStream => _radiusStreamController.stream;

  /// Atualiza o raio com debounce
  /// 
  /// Só persiste no Firestore após 500ms sem mudanças
  void updateRadius(double newRadius) {
    // Validar limites
    if (newRadius < minRadius || newRadius > maxRadius) {
      return;
    }

    // Atualizar valor local imediatamente
    _radiusKm = newRadius;
    notifyListeners();

    // Cancelar timer anterior
    _debounceTimer?.cancel();

    // Criar novo timer
    _debounceTimer = Timer(debounceDuration, () {
      _saveToFirestore();
    });
  }

  /// Carrega o raio do Firestore
  Future<void> _loadFromFirestore() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        final savedRadius = data['radiusKm'] as double?;

        if (savedRadius != null &&
            savedRadius >= minRadius &&
            savedRadius <= maxRadius) {
          _radiusKm = savedRadius;
          notifyListeners();
          _radiusStreamController.add(_radiusKm);
        }
      }
    } catch (e) {
      debugPrint('❌ RadiusController: Erro ao carregar raio: $e');
    }
  }

  /// Salva o raio no Firestore
  Future<void> _saveToFirestore() async {
    if (_isUpdating) return;

    _isUpdating = true;
    notifyListeners();

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
      
      // Verificar se documento existe
      final docSnapshot = await userRef.get();
      
      if (docSnapshot.exists) {
        // Atualizar documento existente
        await userRef.update({
          'radiusKm': _radiusKm,
          'radiusUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Criar documento com dados mínimos
        await userRef.set({
          'radiusKm': _radiusKm,
          'radiusUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Emitir evento no stream
      _radiusStreamController.add(_radiusKm);

      debugPrint('✅ RadiusController: Raio atualizado para $_radiusKm km');
    } catch (e) {
      debugPrint('❌ RadiusController: Erro ao salvar raio: $e');
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  /// Força salvamento imediato (sem debounce)
  Future<void> saveImmediately() async {
    _debounceTimer?.cancel();
    await _saveToFirestore();
  }

  /// Reseta para valor padrão
  void reset() {
    updateRadius(25.0);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _radiusStreamController.close();
    super.dispose();
  }
}
