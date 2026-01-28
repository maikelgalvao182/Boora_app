import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Serviço de cache persistente usando Hive
/// 
/// 🧠 Filosofia: Hive não é banco local. É acelerador de UI.
/// - "Isso ajuda o app a parecer rápido?" → Hive
/// - "Isso define a verdade?" → Firestore
/// 
/// Características:
/// - Cache persistente (sobrevive ao fechar app)
/// - TTL por entrada (Time To Live)
/// - O(1) para leitura/escrita por key
/// - NÃO INDEXA internamente (use key = quadkey, valor = lista pronta)
/// 
/// Uso:
/// ```dart
/// final cache = HiveCacheService<EventLocation>('events');
/// await cache.initialize();
/// 
/// // Salvar
/// await cache.put('quadkey_123', eventsList, ttl: Duration(minutes: 20));
/// 
/// // Recuperar (null se expirado ou não existe)
/// final events = cache.get('quadkey_123');
/// ```
class HiveCacheService<T> {
  final String boxName;
  final String _metaBoxName;
  
  Box<T>? _box;
  Box<int>? _metaBox; // Armazena timestamps de expiração
  
  bool _initialized = false;
  bool debugMode = false;

  HiveCacheService(this.boxName) : _metaBoxName = '${boxName}_meta';

  /// Verifica se o serviço está inicializado
  bool get isInitialized => _initialized;

  /// Inicializa o box do Hive
  /// 
  /// Deve ser chamado após Hive.initFlutter() e registro de adapters
  Future<void> initialize() async {
    if (_initialized) return;
    
    _box = await Hive.openBox<T>(boxName);
    _metaBox = await Hive.openBox<int>(_metaBoxName);
    _initialized = true;
    
    _log('Initialized: $boxName (${_box!.length} entries)');
    
    // Limpa entradas expiradas no startup
    await clearExpired();
  }

  /// Recupera valor do cache
  /// 
  /// Retorna null se:
  /// - Key não existe
  /// - Entry expirou (remove automaticamente)
  /// - Box não inicializado
  T? get(String key) {
    if (!_initialized || _box == null) {
      _log('GET FAILED: Box not initialized');
      return null;
    }
    
    final expiresAt = _metaBox?.get(key);
    
    if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
      // Expirado - remove e retorna null
      _box!.delete(key);
      _metaBox!.delete(key);
      _log('CACHE EXPIRED: $key');
      return null;
    }
    
    T? value;
    try {
      value = _box!.get(key);
    } catch (e) {
      _log('CACHE READ ERROR: $key ($e)');
      _box!.delete(key);
      _metaBox!.delete(key);
      return null;
    }
    
    if (value == null) {
      _log('CACHE MISS: $key');
    } else {
      final remainingSec = expiresAt != null 
          ? ((expiresAt - DateTime.now().millisecondsSinceEpoch) / 1000).round()
          : 0;
      _log('CACHE HIT: $key (expires in ${remainingSec}s)');
    }
    
    return value;
  }

  /// Armazena valor no cache com TTL
  /// 
  /// [key] - Identificador único (ex: quadkey para eventos)
  /// [value] - Valor a ser armazenado
  /// [ttl] - Tempo de vida (padrão: 20 minutos)
  Future<void> put(
    String key, 
    T value, {
    Duration ttl = const Duration(minutes: 20),
  }) async {
    if (!_initialized || _box == null) {
      _log('PUT FAILED: Box not initialized');
      return;
    }
    
    final expiresAt = DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    
    await _box!.put(key, value);
    await _metaBox!.put(key, expiresAt);
    
    _log('CACHE SET: $key (TTL: ${ttl.inMinutes}min)');
  }

  /// Atualiza TTL de uma entrada existente sem reescrever o valor
  /// 
  /// Útil para "touch" de cache - estender validade sem modificar dados
  Future<void> touch(String key, {Duration ttl = const Duration(minutes: 20)}) async {
    if (!_initialized || _metaBox == null) return;
    if (!_box!.containsKey(key)) return;
    
    final expiresAt = DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    await _metaBox!.put(key, expiresAt);
    
    _log('CACHE TOUCH: $key (new TTL: ${ttl.inMinutes}min)');
  }

  /// Remove uma entrada específica
  Future<void> delete(String key) async {
    if (!_initialized) return;
    
    await _box?.delete(key);
    await _metaBox?.delete(key);
    
    _log('CACHE DELETE: $key');
  }

  /// Verifica se uma key existe e não expirou
  bool containsKey(String key) {
    if (!_initialized) return false;
    
    final expiresAt = _metaBox?.get(key);
    if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
      return false;
    }
    
    return _box?.containsKey(key) ?? false;
  }

  /// Retorna todas as keys válidas (não expiradas)
  List<String> get keys {
    if (!_initialized || _box == null) return [];
    
    final now = DateTime.now().millisecondsSinceEpoch;
    return _box!.keys.cast<String>().where((key) {
      final expiresAt = _metaBox?.get(key);
      return expiresAt == null || expiresAt > now;
    }).toList();
  }

  /// Número de entradas válidas
  int get length => keys.length;

  /// Limpa todo o cache
  Future<void> clear() async {
    if (!_initialized) return;
    
    final count = _box?.length ?? 0;
    await _box?.clear();
    await _metaBox?.clear();
    
    _log('CACHE CLEARED: $count entries removed');
  }

  /// Limpa apenas entradas expiradas
  /// 
  /// Chamado automaticamente no initialize()
  /// Pode ser chamado periodicamente para liberar espaço
  Future<int> clearExpired() async {
    if (!_initialized || _box == null || _metaBox == null) return 0;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredKeys = <String>[];
    
    for (final key in _metaBox!.keys.cast<String>()) {
      final expiresAt = _metaBox!.get(key);
      if (expiresAt != null && expiresAt < now) {
        expiredKeys.add(key);
      }
    }
    
    for (final key in expiredKeys) {
      await _box!.delete(key);
      await _metaBox!.delete(key);
    }
    
    if (expiredKeys.isNotEmpty) {
      _log('CACHE CLEANUP: ${expiredKeys.length} expired entries removed');
    }
    
    return expiredKeys.length;
  }

  /// Fecha o box (chamado no dispose do app, se necessário)
  Future<void> close() async {
    await _box?.close();
    await _metaBox?.close();
    _initialized = false;
    _log('CACHE CLOSED: $boxName');
  }

  void _log(String message) {
    if (debugMode) {
      debugPrint('📦 HiveCache[$boxName]: $message');
    }
  }
}

/// Serviço de cache para listas com limite de tamanho
/// 
/// Ideal para conversas, notificações, mensagens
/// Mantém apenas os N itens mais recentes
class HiveListCacheService<T> extends HiveCacheService<List<T>> {
  final int maxItems;
  
  HiveListCacheService(super.boxName, {this.maxItems = 50});

  /// Adiciona itens à lista existente, respeitando o limite
  /// 
  /// [items] - Novos itens a adicionar
  /// [key] - Chave da lista (default: 'default')
  /// [sortBy] - Função para ordenar antes de truncar
  Future<void> addItems(
    List<T> items, {
    String key = 'default',
    int Function(T a, T b)? sortBy,
    Duration ttl = const Duration(minutes: 20),
  }) async {
    final existing = get(key) ?? [];
    
    // Combina e remove duplicatas (se T implementar == corretamente)
    final combined = <T>{...existing, ...items}.toList();
    
    // Ordena se fornecido
    if (sortBy != null) {
      combined.sort(sortBy);
    }
    
    // Trunca para o limite
    final truncated = combined.length > maxItems 
        ? combined.sublist(0, maxItems) 
        : combined;
    
    await put(key, truncated, ttl: ttl);
  }
}
