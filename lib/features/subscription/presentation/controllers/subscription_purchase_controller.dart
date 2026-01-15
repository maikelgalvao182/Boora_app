import 'package:partiu/features/subscription/domain/subscription_plan.dart';
import 'package:partiu/features/subscription/providers/simple_subscription_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionPurchaseController extends ChangeNotifier {
  SubscriptionPurchaseController({
    required this.provider,
    required this.onSuccess,
    required this.onError,
  });

  bool _isDisposed = false;

  final SimpleSubscriptionProvider provider;
  final VoidCallback onSuccess;
  final Function(String error) onError;

  bool _isLoading = false;
  bool _isPurchasing = false;
  String? _error;
  SubscriptionPlan _selectedPlan = SubscriptionPlan.annual;

  bool get isLoading => _isLoading;
  bool get isPurchasing => _isPurchasing;
  String? get error => _error;
  SubscriptionPlan get selectedPlan => _selectedPlan;

  /// Pacotes direto do provider (não guarda estado duplicado)
  Package? get monthlyPackage {
    final packages = provider.offering?.availablePackages;
    if (packages == null || packages.isEmpty) {
      debugPrint('❌ monthlyPackage: packages é null ou vazio');
      return null;
    }

    debugPrint('🔍 Buscando monthly package entre ${packages.length} packages');
    for (final p in packages) {
      debugPrint('  - Package: ${p.identifier} | Type: ${p.packageType} | Product: ${p.storeProduct.identifier}');
    }

    try {
      // 1. Tenta pelo tipo oficial (mais seguro)
      final pkg = packages.firstWhere((p) => p.packageType == PackageType.monthly);
      debugPrint('✅ Monthly package encontrado pelo tipo: ${pkg.identifier}');
      return pkg;
    } catch (_) {
      debugPrint('⚠️  Monthly package não encontrado pelo tipo, tentando fallback...');
      // 2. Fallback: Tenta pelo ID (se o tipo não estiver configurado corretamente)
      try {
        final pkg = packages.firstWhere((p) {
          final id = p.storeProduct.identifier.toLowerCase();
          // Busca por: month, mensal, ou o ID específico mensal_02
          return id.contains('month') || 
                 id.contains('mensal') || 
                 id == 'mensal_02';
        });
        debugPrint('✅ Monthly package encontrado pelo ID: ${pkg.identifier}');
        return pkg;
      } catch (_) {
        debugPrint('❌ Monthly package não encontrado');
        return null;
      }
    }
  }

  Package? get annualPackage {
    final packages = provider.offering?.availablePackages;
    if (packages == null || packages.isEmpty) {
      debugPrint('❌ annualPackage: packages é null ou vazio');
      return null;
    }

    debugPrint('🔍 Buscando annual package entre ${packages.length} packages');

    try {
      // 1. Tenta pelo tipo oficial
      final pkg = packages.firstWhere((p) => p.packageType == PackageType.annual);
      debugPrint('✅ Annual package encontrado pelo tipo: ${pkg.identifier}');
      return pkg;
    } catch (_) {
      debugPrint('⚠️  Annual package não encontrado pelo tipo, tentando fallback...');
      // 2. Fallback: Tenta pelo ID
      try {
        final pkg = packages.firstWhere((p) {
          final id = p.storeProduct.identifier.toLowerCase();
          // Busca por: year, annual, anual, ou o ID específico anual_03
          return id.contains('year') || 
                 id.contains('annual') || 
                 id.contains('anual') ||
                 id == 'anual_03';
        });
        debugPrint('✅ Annual package encontrado pelo ID: ${pkg.identifier}');
        return pkg;
      } catch (_) {
        debugPrint('❌ Annual package não encontrado');
        return null;
      }
    }
  }

  Package? get weeklyPackage {
    final packages = provider.offering?.availablePackages;
    if (packages == null || packages.isEmpty) {
      debugPrint('❌ weeklyPackage: packages é null ou vazio');
      return null;
    }

    debugPrint('🔍 Buscando weekly package entre ${packages.length} packages');

    try {
      // 1. Tenta pelo tipo oficial
      final pkg = packages.firstWhere((p) => p.packageType == PackageType.weekly);
      debugPrint('✅ Weekly package encontrado pelo tipo: ${pkg.identifier}');
      return pkg;
    } catch (_) {
      debugPrint('⚠️  Weekly package não encontrado pelo tipo, tentando fallback...');
      // 2. Fallback: Tenta pelo ID
      try {
        final pkg = packages.firstWhere((p) {
          final id = p.storeProduct.identifier.toLowerCase();
          // Busca por: week, semanal, ou o ID específico semanal_01
          return id.contains('week') || 
                 id.contains('semanal') ||
                 id == 'semanal_01';
        });
        debugPrint('✅ Weekly package encontrado pelo ID: ${pkg.identifier}');
        return pkg;
      } catch (_) {
        debugPrint('❌ Weekly package não encontrado');
        return null;
      }
    }
  }

  Package? get selectedPackage => switch (_selectedPlan) {
    SubscriptionPlan.annual => annualPackage,
    SubscriptionPlan.monthly => monthlyPackage,
    SubscriptionPlan.weekly => weeklyPackage,
  };

  bool get hasPlans => provider.offering?.availablePackages.isNotEmpty == true;

  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Inicializa carregando apenas uma vez
  Future<void> initialize() async {
    if (provider.offering != null) return; // já está pronto

    _isLoading = true;
    _safeNotify();

    try {
      await provider.init(); // provider carrega a offering
    } catch (e) {
      _error = e.toString();
      onError(_error!);
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Selecionar plano
  void selectPlan(SubscriptionPlan plan) {
    _selectedPlan = plan;
    _safeNotify();
  }

  /// Realizar compra
  Future<void> purchaseSelected() async {
    final package = selectedPackage;
    if (package == null) {
      onError('No package selected');
      return;
    }

    if (_isPurchasing) return;

    _isPurchasing = true;
    _safeNotify();

    try {
      await provider.purchase(package);

      // O provider já faz refresh() do MonitoringService após a compra
      // Verifica imediatamente o acesso
      debugPrint('🔍 Verificando acesso VIP após compra: ${provider.hasVipAccess}');
      
      if (provider.hasVipAccess) {
        debugPrint('✅ Acesso VIP confirmado!');
        onSuccess();
      } else {
        // Se ainda não sincronizou, aguarda um pouco mais
        debugPrint('⏳ Acesso não confirmado imediatamente, aguardando sincronização...');
        final hasAccess = await _waitForAccessSync();
        
        if (hasAccess) {
          debugPrint('✅ Acesso VIP confirmado após aguardar!');
          onSuccess();
        } else {
          debugPrint('❌ Acesso VIP não confirmado após timeout');
          onError('Purchase completed but access not active');
        }
      }
    } catch (e) {
      final msg = e.toString();

      if (msg.contains('PURCHASE_CANCELLED')) {
        onError('Payment cancelled');
      } else {
        onError(msg);
      }
    } finally {
      _isPurchasing = false;
      _safeNotify();
    }
  }

  /// Aguarda até 5 segundos para o RevenueCat sincronizar o entitlement
  Future<bool> _waitForAccessSync() async {
    debugPrint('⏳ Aguardando sincronização do RevenueCat...');
    
    const maxAttempts = 10; // 10 tentativas
    const delay = Duration(milliseconds: 500); // 500ms entre tentativas
    
    for (int i = 0; i < maxAttempts; i++) {
      if (provider.hasVipAccess) {
        debugPrint('✅ Acesso VIP sincronizado após ${i * 500}ms');
        return true;
      }
      
      if (i < maxAttempts - 1) {
        await Future.delayed(delay);
      }
    }
    
    debugPrint('⚠️  Timeout: VIP não sincronizado após 5 segundos');
    return false;
  }

  /// Restaurar compras
  Future<void> restorePurchases() async {
    try {
      await provider.restorePurchases();

      // Aguarda sincronização do RevenueCat (até 5 segundos)
      final hasAccess = await _waitForAccessSync();

      if (hasAccess) {
        onSuccess();
      } else {
        onError('No previous purchases found');
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<void> retry() => initialize();
}
