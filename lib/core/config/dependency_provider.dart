import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:partiu/shared/repositories/auth_repository.dart';
import 'package:partiu/shared/repositories/auth_repository_interface.dart';
import 'package:partiu/features/auth/presentation/controllers/sign_in_view_model.dart';
import 'package:partiu/features/auth/presentation/controllers/email_auth_view_model.dart';
import 'package:partiu/features/auth/presentation/controllers/cadastro_view_model.dart';
import 'package:partiu/features/location/data/repositories/location_repository.dart';
import 'package:partiu/features/location/domain/repositories/location_repository_interface.dart';
import 'package:partiu/features/location/presentation/viewmodels/update_location_view_model.dart';
import 'package:partiu/features/profile/presentation/viewmodels/profile_tab_view_model.dart';
import 'package:partiu/features/profile/presentation/viewmodels/edit_profile_view_model_refactored.dart';
import 'package:partiu/features/profile/presentation/viewmodels/edit_profile_view_model.dart';
import 'package:partiu/features/profile/presentation/viewmodels/image_upload_view_model.dart';
import 'package:partiu/features/profile/data/repositories/profile_repository.dart';
import 'package:partiu/features/profile/domain/repositories/profile_repository_interface.dart';
import 'package:partiu/core/services/image_picker_service.dart';
import 'package:partiu/core/services/location_service.dart';
import 'package:partiu/core/services/location_permission_flow.dart';
import 'package:partiu/core/services/location_cache.dart';
import 'package:partiu/core/services/location_analytics_service.dart';
import 'package:partiu/core/services/geo_index_service.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository.dart';
import 'package:partiu/features/notifications/services/activity_notification_service.dart';
import 'package:partiu/features/notifications/services/user_affinity_service.dart';
import 'package:partiu/features/notifications/services/notification_targeting_service.dart';
import 'package:partiu/features/notifications/services/notification_orchestrator.dart';
import 'package:partiu/features/home/create_flow/activity_repository.dart';

/// Sistema de injeção de dependências usando get_it
class DependencyProvider extends InheritedWidget {
  const DependencyProvider({
    super.key,
    required super.child,
    required this.serviceLocator,
  });

  final ServiceLocator serviceLocator;

  static DependencyProvider of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<DependencyProvider>();
    assert(result != null, 'No DependencyProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(DependencyProvider oldWidget) => false;
}

/// Service Locator usando get_it
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  final GetIt _getIt = GetIt.instance;

  /// Inicializa todas as dependências
  Future<void> init() async {
    debugPrint("🚀 [ServiceLocator] init() chamado!"); // DIAGNOSTIC LOG
    debugPrint("🔧 [ServiceLocator] Iniciando registro de dependências...");
    
    // Repositories
    _getIt.registerLazySingleton<IAuthRepository>(() => AuthRepository());
    _getIt.registerLazySingleton<LocationRepositoryInterface>(() => LocationRepository());
    _getIt.registerLazySingleton<IProfileRepository>(() => ProfileRepository());
    _getIt.registerLazySingleton<INotificationsRepository>(() => NotificationsRepository());
    
    // Services
    _getIt.registerLazySingleton<ImagePickerService>(() => ImagePickerService());
    
    // 🗺️ Location Services (Enterprise Architecture)
    _getIt.registerLazySingleton<LocationService>(() => LocationService());
    _getIt.registerLazySingleton<LocationPermissionFlow>(() => LocationPermissionFlow());
    _getIt.registerLazySingleton<LocationCache>(() => LocationCache.instance);
    _getIt.registerLazySingleton<LocationAnalyticsService>(() => LocationAnalyticsService.instance);
    // LocationSyncScheduler é inicializado no main.dart
    
    // 🌍 Geo Services (CAMADA 0 - Infraestrutura Geográfica)
    _getIt.registerLazySingleton<GeoIndexService>(() => GeoIndexService());
    
    // 💖 Affinity Services (CAMADA 1 - Cálculo de Afinidade)
    _getIt.registerLazySingleton<UserAffinityService>(() => UserAffinityService());
    
    // 🎯 Targeting Services (CAMADA 2 - Targeting de Notificações)
    _getIt.registerLazySingleton<NotificationTargetingService>(
      () => NotificationTargetingService(
        geoService: _getIt<GeoIndexService>(),
        affinityService: _getIt<UserAffinityService>(),
      ),
    );
    
    // 📢 Orchestrator (CAMADA 3 - Orquestração de Criação)
    _getIt.registerLazySingleton<NotificationOrchestrator>(
      () => NotificationOrchestrator(),
    );
    
    // 🔔 Notification Services (CAMADA 4 - Services Legados)
    _getIt.registerLazySingleton<ActivityNotificationService>(
      () => ActivityNotificationService(
        notificationRepository: _getIt<INotificationsRepository>(),
        targetingService: _getIt<NotificationTargetingService>(),
        orchestrator: _getIt<NotificationOrchestrator>(),
      ),
    );
    
    // Activity Repository
    _getIt.registerLazySingleton<ActivityRepository>(
      () => ActivityRepository(
        notificationService: _getIt<ActivityNotificationService>(),
      ),
    );

    // ViewModels
    _getIt.registerFactory<SignInViewModel>(
      () => SignInViewModel(authRepository: _getIt<IAuthRepository>()),
    );
    _getIt.registerFactory<EmailAuthViewModel>(() => EmailAuthViewModel());
    _getIt.registerFactory<CadastroViewModel>(() => CadastroViewModel());
    _getIt.registerFactory<UpdateLocationViewModel>(
      () => UpdateLocationViewModel(
        locationRepository: _getIt<LocationRepositoryInterface>(),
        locationService: _getIt<LocationService>(),
        permissionFlow: _getIt<LocationPermissionFlow>(),
      ),
    );
    _getIt.registerFactory<ProfileTabViewModel>(() => ProfileTabViewModel());
    _getIt.registerFactory<EditProfileViewModelRefactored>(
      () => EditProfileViewModelRefactored(authRepository: _getIt<IAuthRepository>() as AuthRepository),
    );
    _getIt.registerFactory<EditProfileViewModel>(
      () => EditProfileViewModel(
        profileRepository: _getIt<IProfileRepository>(),
        imagePickerService: _getIt<ImagePickerService>(),
      ),
    );
    _getIt.registerLazySingleton<ImageUploadViewModel>(() {
      debugPrint("[ServiceLocator] 📦 Registering ImageUploadViewModel");
      return ImageUploadViewModel();
    });
    
    debugPrint("✅ [ServiceLocator] Todas as dependências registradas com sucesso!");
    debugPrint("📋 [ServiceLocator] ImageUploadViewModel registrado: ${_getIt.isRegistered<ImageUploadViewModel>()}");
  }

  T get<T extends Object>() {
    debugPrint("🔍 [ServiceLocator] Requesting dependency: $T");
    try {
      final instance = _getIt.get<T>();
      debugPrint("✅ [ServiceLocator] Successfully obtained: $T");
      return instance;
    } catch (e) {
      debugPrint("❌ [ServiceLocator] Failed to get $T: $e");
      rethrow;
    }
  }

  void register<T extends Object>(T instance) {
    if (!_getIt.isRegistered<T>()) {
      _getIt.registerSingleton<T>(instance);
    }
  }
}
