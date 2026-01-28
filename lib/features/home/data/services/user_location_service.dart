import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// Resultado da tentativa de obter localização
class LocationResult {
  final LatLng location;
  final bool isDefaultLocation;
  final String? errorMessage;

  const LocationResult({
    required this.location,
    this.isDefaultLocation = false,
    this.errorMessage,
  });

  bool get hasError => errorMessage != null;
}

/// Serviço responsável por gerenciar localização do usuário
/// 
/// Responsabilidades:
/// - Verificar permissões
/// - Obter localização atual
/// - Fornecer fallback quando necessário
/// - Mensagens de erro amigáveis
class UserLocationService {
  /// Localização padrão (São Paulo)
  static const LatLng defaultLocation = LatLng(-23.5505, -46.6333);

  /// Obtém a localização atual do usuário
  /// 
  /// Retorna [LocationResult] contendo:
  /// - location: coordenadas (atual ou fallback)
  /// - isDefaultLocation: true se usou fallback
  /// - errorMessage: descrição do erro (se houver)
  Future<LocationResult> getUserLocation() async {
    try {
      // 1. Verificar se o serviço de localização está ativo
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationResult(
          location: defaultLocation,
          isDefaultLocation: true,
          errorMessage: 'Ative o GPS para ver sua localização',
        );
      }

      // 2. Verificar permissões
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Solicitar permissão
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          return const LocationResult(
            location: defaultLocation,
            isDefaultLocation: true,
            errorMessage: 'Permissão de localização negada',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(
          location: defaultLocation,
          isDefaultLocation: true,
          errorMessage: 'Permissão negada. Ative nas configurações do app',
        );
      }

      // 3. Tentar obter a última posição conhecida (rápido e não bloqueante)
      // No Android/iOS, isso retorna a última leitura de GPS/Wi-Fi armazenada pelo sistema.
      // Útil para evitar timeout se o GPS estiver demorando para travar.
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LocationResult(
          location: LatLng(lastKnown.latitude, lastKnown.longitude),
          isDefaultLocation: false,
        );
      }

      // 4. Se não houver última posição, tenta obter posição atual com timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // Medium é mais rápido que High e suficiente para carregar o mapa inicial
        ),
      ).timeout(
        const Duration(seconds: 8), // Aumentado um pouco para evitar falso negativo em dispositivos lentos
        onTimeout: () => throw TimeoutException('Timeout ao obter localização'),
      );

      return LocationResult(
        location: LatLng(position.latitude, position.longitude),
        isDefaultLocation: false,
      );
    } on LocationServiceDisabledException {
      return const LocationResult(
        location: defaultLocation,
        isDefaultLocation: true,
        errorMessage: 'Ative o GPS nas configurações',
      );
    } on PermissionDeniedException {
      return const LocationResult(
        location: defaultLocation,
        isDefaultLocation: true,
        errorMessage: 'Permissão de localização necessária',
      );
    } on TimeoutException {
      return const LocationResult(
        location: defaultLocation,
        isDefaultLocation: true,
        errorMessage: 'Timeout ao obter localização',
      );
    } catch (e) {
      return const LocationResult(
        location: defaultLocation,
        isDefaultLocation: true,
        errorMessage: 'Erro ao obter localização',
      );
    }
  }

  /// Obtém localização de forma simples (sem detalhes de erro)
  /// 
  /// Útil quando você só precisa das coordenadas
  Future<LatLng> getLocationOrDefault() async {
    final result = await getUserLocation();
    return result.location;
  }

  /// Verifica se as permissões estão concedidas
  Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Stream de atualizações de localização
  /// 
  /// Útil para rastrear movimento do usuário em tempo real
  Stream<LatLng> watchUserLocation({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration interval = const Duration(seconds: 5),
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: 10, // metros
        timeLimit: interval,
      ),
    ).map((position) => LatLng(position.latitude, position.longitude));
  }
}
