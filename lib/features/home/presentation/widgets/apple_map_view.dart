import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Widget de mapa Apple Maps limpo e performático
/// 
/// Este widget:
/// - Renderiza o Apple Map uma única vez
/// - Exibe a localização do usuário (ponto azul)
/// - Fornece métodos para animar a câmera
/// - Sem markers, overlays ou complexidades desnecessárias
class AppleMapView extends StatefulWidget {
  const AppleMapView({super.key});

  @override
  State<AppleMapView> createState() => _AppleMapViewState();
}

class _AppleMapViewState extends State<AppleMapView> {
  /// Controller do mapa Apple Maps
  AppleMapController? _mapController;
  
  /// Flag para saber se o mapa foi inicializado
  /// Usado apenas para controle interno, NÃO para recriar o mapa
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    // Nada pesado aqui - inicialização leve
  }

  /// Callback chamado quando o mapa é criado
  /// Armazena o controller para uso posterior
  void _onMapCreated(AppleMapController controller) {
    _mapController = controller;
    setState(() {
      _mapReady = true;
    });
    
    // Opcional: mover para localização do usuário automaticamente
    _moveCameraToUserLocation();
  }

  /// Move a câmera para uma coordenada específica com animação
  /// 
  /// Parâmetros:
  /// - [lat]: Latitude de destino
  /// - [lng]: Longitude de destino
  /// - [zoom]: Nível de zoom (padrão: 14)
  Future<void> _moveCameraTo(
    double lat,
    double lng, {
    double zoom = 14.0,
  }) async {
    if (_mapController == null || !_mapReady) {
      debugPrint('⚠️ Mapa ainda não está pronto para animação');
      return;
    }

    try {
      // Anima a câmera para a nova posição
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: zoom,
          ),
        ),
      );
      debugPrint('✅ Câmera movida para: $lat, $lng');
    } catch (e) {
      debugPrint('❌ Erro ao mover câmera: $e');
    }
  }

  /// Move a câmera para a localização atual do usuário
  /// 
  /// Este método:
  /// 1. Verifica permissões de localização
  /// 2. Obtém a posição atual usando Geolocator
  /// 3. Anima a câmera até a localização
  /// 4. Trata erros comuns (permissão negada, GPS desligado, etc.)
  Future<void> _moveCameraToUserLocation() async {
    try {
      // 1. Verificar se o serviço de localização está ativo
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ Serviço de localização desativado');
        if (mounted) {
          _showLocationMessage('Ative o GPS para ver sua localização');
        }
        return;
      }

      // 2. Verificar permissões
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        // Solicitar permissão
        permission = await Geolocator.requestPermission();
        
        if (permission == LocationPermission.denied) {
          debugPrint('⚠️ Permissão de localização negada');
          if (mounted) {
            _showLocationMessage('Permissão de localização negada');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Permissão de localização negada permanentemente');
        if (mounted) {
          _showLocationMessage(
            'Permissão negada. Ative nas configurações do app',
          );
        }
        return;
      }

      // 3. Obter posição atual
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      debugPrint('📍 Localização obtida: ${position.latitude}, ${position.longitude}');

      // 4. Mover câmera para a localização
      await _moveCameraTo(
        position.latitude,
        position.longitude,
        zoom: 15.0,
      );
    } on LocationServiceDisabledException {
      debugPrint('❌ Serviço de localização está desabilitado');
      if (mounted) {
        _showLocationMessage('Ative o GPS nas configurações');
      }
    } on PermissionDeniedException {
      debugPrint('❌ Permissão de localização negada');
      if (mounted) {
        _showLocationMessage('Permissão de localização necessária');
      }
    } catch (e) {
      debugPrint('❌ Erro ao obter localização: $e');
      if (mounted) {
        _showLocationMessage('Erro ao obter localização');
      }
    }
  }

  /// Exibe mensagem de feedback para o usuário
  void _showLocationMessage(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ IMPORTANTE: O mapa é criado UMA VEZ aqui no build()
    // Não será recriado quando _mapReady mudar de false -> true
    // O AppleMap é imutável e performático
    return AppleMap(
      // Callback de criação do mapa
      onMapCreated: _onMapCreated,
      
      // Posição inicial da câmera (São Paulo como padrão)
      initialCameraPosition: const CameraPosition(
        target: LatLng(-23.5505, -46.6333),
        zoom: 12.0,
      ),
      
      // Exibir localização do usuário (ponto azul)
      myLocationEnabled: true,
      
      // Desabilitar botão de localização padrão
      // (você pode implementar seu próprio botão customizado se quiser)
      myLocationButtonEnabled: false,
      
      // Tipo do mapa (standard = padrão do Apple Maps)
      mapType: MapType.standard,
      
      // Permitir gestos de interação
      compassEnabled: true,
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
    );
  }

  @override
  void dispose() {
    // Cleanup do controller se necessário
    _mapController = null;
    super.dispose();
  }
}
