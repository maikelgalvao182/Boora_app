// 🎯 EXEMPLOS DE USO - Sistema de Filtro por Raio

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/location_stream_controller.dart';
import 'package:partiu/services/location/radius_controller.dart';
import 'package:partiu/services/location/distance_isolate.dart';
import 'package:partiu/services/location/geo_utils.dart';

// ============================================================================
// 1. USO BÁSICO - Buscar eventos uma vez
// ============================================================================

void exemploBasico() async {
  final service = LocationQueryService();
  
  // Buscar eventos com raio do usuário
  final eventos = await service.getEventsWithinRadiusOnce();
  
  // ignore: avoid_print
  print('${eventos.length} eventos encontrados');
  
  for (final evento in eventos) {
    // ignore: avoid_print
    print('${evento.eventData['activityText']} - ${evento.distanceKm.toStringAsFixed(1)} km');
  }
}

// ============================================================================
// 2. USO COM RAIO CUSTOMIZADO
// ============================================================================

void exemploRaioCustomizado() async {
  final service = LocationQueryService();
  
  // Buscar eventos em raio de 50km (ignora preferência do usuário)
  final eventos = await service.getEventsWithinRadiusOnce(
    customRadiusKm: 50.0,
  );
  
  // ignore: avoid_print
  print('Eventos em 50km: ${eventos.length}');
}

// ============================================================================
// 3. USO COM STREAM (Atualização automática)
// ============================================================================

class EventListController {
  StreamSubscription<List<EventWithDistance>>? _subscription;
  
  void startListening() {
    final service = LocationQueryService();
    
    _subscription = service.eventsStream.listen((eventos) {
      // ignore: avoid_print
      print('📡 Eventos atualizados: ${eventos.length}');
      // Atualizar UI aqui
    });
  }
  
  void dispose() {
    _subscription?.cancel();
  }
}

// ============================================================================
// 4. CONTROLAR RAIO MANUALMENTE
// ============================================================================

class RaioWidget extends StatefulWidget {
  const RaioWidget({super.key});

  @override
  State<RaioWidget> createState() => _RaioWidgetState();
}

class _RaioWidgetState extends State<RaioWidget> {
  final _radiusController = RadiusController();
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _radiusController,
      builder: (context, _) {
        return Column(
          children: [
            Text('Raio: ${_radiusController.radiusKm.toInt()} km'),
            
            Slider(
              value: _radiusController.radiusKm,
              min: RadiusController.minRadius,
              max: RadiusController.maxRadius,
              onChanged: (value) {
                _radiusController.updateRadius(value);
              },
            ),
            
            if (_radiusController.isUpdating)
              const CircularProgressIndicator(),
          ],
        );
      },
    );
  }
}

// ============================================================================
// 5. OUVIR MUDANÇAS DE RAIO (Observer Pattern)
// ============================================================================

class MapaController {
  StreamSubscription<double>? _radiusSubscription;
  
  void initListeners() {
    final streamController = LocationStreamController();
    
    // Ouvir mudanças de raio
    _radiusSubscription = streamController.radiusStream.listen((novoRaio) {
      // ignore: avoid_print
      print('🔄 Raio mudou para $novoRaio km');
      _recarregarMapa();
    });
  }
  
  void _recarregarMapa() {
    // Lógica de recarga aqui
  }
  
  void dispose() {
    _radiusSubscription?.cancel();
  }
}

// ============================================================================
// 6. CALCULAR DISTÂNCIA ENTRE PONTOS
// ============================================================================

void exemploCalculoDistancia() {
  // Distância entre Av. Paulista e Ibirapuera
  final distancia = GeoUtils.calculateDistance(
    lat1: -23.5613, lng1: -46.6565, // Paulista
    lat2: -23.5873, lng2: -46.6577, // Ibirapuera
  );
  
  // ignore: avoid_print
  print('Distância: ${distancia.toStringAsFixed(2)} km'); // ~2.90 km
}

// ============================================================================
// 7. VERIFICAR SE PONTO ESTÁ DENTRO DO RAIO
// ============================================================================

void exemploVerificarRaio() {
  final dentroDoRaio = GeoUtils.isWithinRadius(
    centerLat: -23.5505,
    centerLng: -46.6333,
    pointLat: -23.5489,
    pointLng: -46.6388,
    radiusKm: 5.0,
  );
  
  if (dentroDoRaio) {
    // ignore: avoid_print
    print('✅ Evento está dentro do raio');
  } else {
    // ignore: avoid_print
    print('❌ Evento está fora do raio');
  }
}

// ============================================================================
// 8. CALCULAR BOUNDING BOX (Para queries Firestore)
// ============================================================================

void exemploBoundingBox() {
  final box = GeoUtils.calculateBoundingBox(
    centerLat: -23.5505,
    centerLng: -46.6333,
    radiusKm: 25.0,
  );
  
  // ignore: avoid_print
  print('Bounding Box:');
  // ignore: avoid_print
  print('Min Lat: ${box['minLat']}');
  // ignore: avoid_print
  print('Max Lat: ${box['maxLat']}');
  // ignore: avoid_print
  print('Min Lng: ${box['minLng']}');
  // ignore: avoid_print
  print('Max Lng: ${box['maxLng']}');
  
  // Usar em query Firestore:
  // .where('latitude', isGreaterThanOrEqualTo: box['minLat'])
  // .where('latitude', isLessThanOrEqualTo: box['maxLat'])
}

// ============================================================================
// 9. FORÇAR RELOAD MANUAL (Invalidar cache)
// ============================================================================

void exemploForceReload() {
  final service = LocationQueryService();
  
  // Invalidar cache e recarregar
  service.forceReload();
  
  // ignore: avoid_print
  print('🔄 Cache invalidado, eventos recarregados');
}

// ============================================================================
// 10. SALVAR RAIO IMEDIATAMENTE (Sem debounce)
// ============================================================================

void exemploSaveImediato() async {
  final controller = RadiusController();
  
  // Mudar raio
  controller.updateRadius(50.0);
  
  // Salvar imediatamente (ignora debounce)
  await controller.saveImmediately();
  
  // ignore: avoid_print
  print('✅ Raio salvo imediatamente');
}

// ============================================================================
// 11. USO EM WIDGET STATELESS (Provider Pattern)
// ============================================================================

class EventosListScreen extends StatelessWidget {
  const EventosListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = LocationQueryService();
    
    return StreamBuilder<List<EventWithDistance>>(
      stream: service.eventsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        
        final eventos = snapshot.data!;
        
        return ListView.builder(
          itemCount: eventos.length,
          itemBuilder: (context, index) {
            final evento = eventos[index];
            return ListTile(
              title: Text(evento.eventData['activityText'] ?? ''),
              subtitle: Text('${evento.distanceKm.toStringAsFixed(1)} km'),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// 12. INTEGRAÇÃO COM VIEWMODEL (MVVM Pattern)
// ============================================================================

class EventosViewModel extends ChangeNotifier {
  final LocationQueryService _service = LocationQueryService();
  StreamSubscription<List<EventWithDistance>>? _subscription;
  
  List<EventWithDistance> _eventos = [];
  List<EventWithDistance> get eventos => _eventos;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  void initialize() {
    _subscription = _service.eventsStream.listen((eventos) {
      _eventos = eventos;
      notifyListeners();
    });
  }
  
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    
    _service.forceReload();
    
    _isLoading = false;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// ============================================================================
// 13. TESTES UNITÁRIOS
// ============================================================================

void testesUnitarios() {
  // Testes foram removidos - criar arquivo separado de testes
}

// ============================================================================
// 14. EXEMPLO COMPLETO - Lista de eventos com filtro
// ============================================================================

class EventosComFiltroScreen extends StatefulWidget {
  const EventosComFiltroScreen({super.key});

  @override
  State<EventosComFiltroScreen> createState() => _EventosComFiltroScreenState();
}

class _EventosComFiltroScreenState extends State<EventosComFiltroScreen> {
  final _radiusController = RadiusController();
  final _service = LocationQueryService();
  StreamSubscription<List<EventWithDistance>>? _subscription;
  List<EventWithDistance> _eventos = [];
  
  @override
  void initState() {
    super.initState();
    _initializeListeners();
  }
  
  void _initializeListeners() {
    // Ouvir mudanças de eventos
    _subscription = _service.eventsStream.listen((eventos) {
      setState(() {
        _eventos = eventos;
      });
    });
    
    // Carregar eventos iniciais
    _service.forceReload();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos Próximos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _service.forceReload(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Slider de raio
          _buildRaioSlider(),
          
          // Lista de eventos
          Expanded(
            child: _buildEventosList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRaioSlider() {
    return ListenableBuilder(
      listenable: _radiusController,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Raio: ${_radiusController.radiusKm.toInt()} km'),
              Slider(
                value: _radiusController.radiusKm,
                min: RadiusController.minRadius,
                max: RadiusController.maxRadius,
                onChanged: (value) {
                  _radiusController.updateRadius(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildEventosList() {
    if (_eventos.isEmpty) {
      return const Center(
        child: Text('Nenhum evento encontrado'),
      );
    }
    
    return ListView.builder(
      itemCount: _eventos.length,
      itemBuilder: (context, index) {
        final evento = _eventos[index];
        final data = evento.eventData;
        
        return ListTile(
          leading: Text(
            data['emoji'] ?? '🎉',
            style: TextStyle(fontSize: 32),
          ),
          title: Text(data['activityText'] ?? ''),
          subtitle: Text('${evento.distanceKm.toStringAsFixed(1)} km'),
          onTap: () {
            // Navegar para detalhes
          },
        );
      },
    );
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
