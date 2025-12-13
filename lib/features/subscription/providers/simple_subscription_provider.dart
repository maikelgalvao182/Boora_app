import 'package:partiu/features/subscription/services/simple_revenue_cat_service.dart';
import 'package:partiu/features/subscription/services/subscription_monitoring_service.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SimpleSubscriptionProvider extends ChangeNotifier {
  SimpleSubscriptionProvider() {
    Future.microtask(init);
  }

  Offering? _offering;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  bool _showingPaywall = false;

  Offering? get offering => _offering;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get showingPaywall => _showingPaywall;

  /// Fonte ÚNICA de verdade para status VIP
  bool get hasVipAccess => SubscriptionMonitoringService.hasVipAccess;

  Future<void> init() async {
    if (_isInitialized) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Carrega oferta apenas 1x
      _offering = await SimpleRevenueCatService.getOffering();
      
      debugPrint('📦 SimpleSubscriptionProvider: Offering carregada');
      debugPrint('  - Offering: ${_offering?.identifier}');
      debugPrint('  - Packages: ${_offering?.availablePackages.length ?? 0}');
      if (_offering != null) {
        for (final pkg in _offering!.availablePackages) {
          debugPrint('    * ${pkg.identifier} (${pkg.packageType})');
        }
      }

      // Escuta mudanças globais da assinatura (do MonitoringService)
      SubscriptionMonitoringService.addVipListener((_) {
        notifyListeners(); // VIP mudou → atualiza UI
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('❌ Erro ao inicializar provider: $e');
      
      // Erro de configuração específico do RevenueCat
      if (e.toString().contains('CONFIGURATION_ERROR')) {
        _error = 'Erro de configuração: Produtos não encontrados no App Store Connect.\n\nPara desenvolvimento iOS, configure um StoreKit Configuration File.\n\nMais info: https://rev.cat/why-are-offerings-empty';
      } else {
        _error = e.toString();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Compra
  Future<void> purchase(Package package) async {
    _isLoading = true;
    notifyListeners();

    try {
      await SimpleRevenueCatService.purchasePackage(package);
      _showingPaywall = false;
      notifyListeners(); // Porque oferta mudou
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Restaurar
  Future<void> restorePurchases() async {
    _isLoading = true;
    notifyListeners();

    try {
      await SimpleRevenueCatService.restorePurchases();
      _showingPaywall = false;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Paywall control
  void showPaywall() {
    _showingPaywall = true;
    notifyListeners();
  }

  void hidePaywall() {
    _showingPaywall = false;
    notifyListeners();
  }
}
