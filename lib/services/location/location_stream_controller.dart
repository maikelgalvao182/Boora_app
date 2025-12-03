import 'dart:async';
import 'package:flutter/foundation.dart';

/// Controller de streams para mudanças de localização e raio
/// 
/// Responsabilidades:
/// - Gerenciar streams broadcast
/// - Notificar múltiplos listeners
/// - Coordenar eventos de localização
class LocationStreamController {
  /// Singleton
  static final LocationStreamController _instance =
      LocationStreamController._internal();
  factory LocationStreamController() => _instance;
  LocationStreamController._internal();

  /// Stream de mudanças de raio
  final _radiusStreamController = StreamController<double>.broadcast();

  /// Stream de mudanças de localização do usuário
  final _userLocationStreamController =
      StreamController<UserLocationEvent>.broadcast();

  /// Stream de eventos de reload
  final _reloadStreamController = StreamController<void>.broadcast();

  /// Getter para stream de raio
  Stream<double> get radiusStream => _radiusStreamController.stream;

  /// Getter para stream de localização
  Stream<UserLocationEvent> get userLocationStream =>
      _userLocationStreamController.stream;

  /// Getter para stream de reload
  Stream<void> get reloadStream => _reloadStreamController.stream;

  /// Emite mudança de raio
  void emitRadiusChange(double radiusKm) {
    if (!_radiusStreamController.isClosed) {
      _radiusStreamController.add(radiusKm);
      debugPrint('📡 LocationStreamController: Raio atualizado para $radiusKm km');
    }
  }

  /// Emite mudança de localização do usuário
  void emitUserLocationChange(double latitude, double longitude) {
    if (!_userLocationStreamController.isClosed) {
      _userLocationStreamController.add(
        UserLocationEvent(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now(),
        ),
      );
      debugPrint(
          '📡 LocationStreamController: Localização atualizada para ($latitude, $longitude)');
    }
  }

  /// Emite evento de reload (força recarga de eventos)
  void emitReload() {
    if (!_reloadStreamController.isClosed) {
      _reloadStreamController.add(null);
      debugPrint('📡 LocationStreamController: Reload solicitado');
    }
  }

  /// Limpa todos os streams
  void dispose() {
    _radiusStreamController.close();
    _userLocationStreamController.close();
    _reloadStreamController.close();
  }
}

/// Evento de mudança de localização do usuário
class UserLocationEvent {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const UserLocationEvent({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  @override
  String toString() =>
      'UserLocationEvent(lat: $latitude, lng: $longitude, time: $timestamp)';
}
