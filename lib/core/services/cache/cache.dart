/// Sistema de cache da aplicação
/// 
/// Imports centralizados:
/// ```dart
/// import 'package:partiu/core/services/cache/cache.dart';
/// 
/// // Use
/// CacheManager.instance.users.getUser(userId);
/// CacheManager.instance.avatars.getAvatarUrl(userId);
/// ```
library;

export 'cache_manager.dart';
export 'user_cache_service.dart';
export 'avatar_cache_service.dart';
export 'hive_cache_service.dart';
