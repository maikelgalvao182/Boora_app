import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:partiu/features/home/data/models/event_location_cache.dart';
import 'package:partiu/core/models/last_known_location_cache.dart';
import 'package:partiu/core/models/user_preferences_cache.dart';
import 'package:partiu/core/models/user_session_cache.dart';
import 'package:partiu/features/conversations/models/conversation_item.dart';
import 'package:partiu/features/notifications/models/notification_cache_item.dart';
import 'package:partiu/screens/chat/models/message_cache_item.dart';
import 'package:partiu/core/models/user_preview_model.dart';

/// Inicializador do Hive para cache persistente
/// 
/// 🧠 Filosofia: Hive não é banco local. É acelerador de UI.
/// 
/// Deve ser chamado no início do app, após WidgetsFlutterBinding.ensureInitialized()
/// e ANTES de qualquer uso de HiveCacheService.
/// 
/// Exemplo:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await HiveInitializer.initialize();
///   // ... resto do app
/// }
/// ```
class HiveInitializer {
  static bool _initialized = false;
  
  /// Verifica se o Hive já foi inicializado
  static bool get isInitialized => _initialized;

  /// Inicializa o Hive e registra todos os adapters
  /// 
  /// Seguro para chamar múltiplas vezes (idempotente)
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Inicializa Hive com path do Flutter
      await Hive.initFlutter();
      
      // Registra adapters customizados
      _registerAdapters();
      
      _initialized = true;
      debugPrint('📦 Hive initialized successfully');
    } catch (e) {
      debugPrint('📦 Hive initialization error: $e');
      // Não propaga erro - cache é opcional, app deve funcionar sem ele
    }
  }

  /// Registra todos os TypeAdapters do Hive
  /// 
  /// TypeId allocation:
  /// - 0-9: Reserved for core types
  /// - 10-19: Events/Map data
  /// - 20-29: User/Profile data
  /// - 30-39: Conversations/Chat data
  /// - 40-49: Notifications data
  /// - 50+: Future use
  static void _registerAdapters() {
    // 10-19: Events/Map data
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(EventLocationCacheAdapter());
    }

    // 20-29: User/Profile data
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(LastKnownLocationCacheAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(UserPreferencesCacheAdapter());
    }
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(UserSessionCacheAdapter());
    }
    // 23-24: User Preview (SWR Strategy)
    if (!Hive.isAdapterRegistered(23)) {
      Hive.registerAdapter(UserPreviewModelAdapter());
    }
    if (!Hive.isAdapterRegistered(24)) {
      Hive.registerAdapter(CachedUserPreviewAdapter());
    }

    // 30-39: Conversations/Chat data
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(ConversationItemAdapter());
    }
    if (!Hive.isAdapterRegistered(31)) {
      Hive.registerAdapter(MessageCacheItemAdapter());
    }

    // 40-49: Notifications data
    if (!Hive.isAdapterRegistered(40)) {
      Hive.registerAdapter(NotificationCacheItemAdapter());
    }
    
    debugPrint('📦 Hive adapters registered');
  }

  /// Limpa todo o cache do Hive (para debug/logout)
  static Future<void> clearAllCaches() async {
    if (!_initialized) return;
    
    try {
      await Hive.deleteFromDisk();
      _initialized = false;
      debugPrint('📦 All Hive caches cleared');
    } catch (e) {
      debugPrint('📦 Error clearing Hive caches: $e');
    }
  }

  /// Fecha todas as boxes do Hive (para cleanup)
  static Future<void> close() async {
    if (!_initialized) return;
    
    try {
      await Hive.close();
      _initialized = false;
      debugPrint('📦 Hive closed');
    } catch (e) {
      debugPrint('📦 Error closing Hive: $e');
    }
  }
}
