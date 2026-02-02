// simple_revenue_cat_service.dart
// ----------------------------------------------------------------------------
// Serviço simplificado do RevenueCat — versão enxuta e estável.
// ----------------------------------------------------------------------------
// Responsabilidade deste arquivo:
//   • Inicializar o SDK
//   • Buscar Offering
//   • Buscar CustomerInfo
//   • Escutar mudanças reais do CustomerInfo (listener oficial)
//   • Comprar / Restaurar
//
// O QUE NÃO FAZ MAIS (porque gerava instabilidade):
//   ✘ timers
//   ✘ polling
//   ✘ loops com retry
//   ✘ watchers duplicados
//   ✘ verificações paranoicas de iOS
//   ✘ análises complexas de entitlement
//
// O restante da lógica (detectar expiração, cancelamento etc.)
// fica no SubscriptionMonitoringService ou no Provider.
// ----------------------------------------------------------------------------

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:partiu/common/utils/app_logger.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SimpleRevenueCatService {
  // --------------------------------------------------------------------------
  // ESTADO INTERNO
  // --------------------------------------------------------------------------
  static bool _initialized = false;
  static bool _disabledForRelease = false;
  static CustomerInfo? _lastInfo;
  static String? _currentRcUserId;

  static String? _entitlementId;
  static String? _offeringId;

  // Listeners locais registrados pela aplicação
  static final _listeners = <void Function(CustomerInfo)>{};

  // --------------------------------------------------------------------------
  // INITIALIZE
  // --------------------------------------------------------------------------
  static Future<void> initialize() async {
    if (_initialized) return;

    AppLogger.info('RevenueCat: inicializando...');

    // 1. Carrega configs (entitlement + offering)
    await _loadConfiguration();

    // 2. Busca API key do Firestore
    final apiKey = await _getApiKey();
    AppLogger.info('RevenueCat: API key resultado: ${apiKey != null ? "encontrada (${apiKey.length} chars)" : "NULL"}');
    
    if (apiKey == null || apiKey.isEmpty) {
      AppLogger.error('❌ RevenueCat API key não encontrada no Firestore!');
      AppLogger.error('   Verifique se o documento AppInfo/revenue_cat existe');
      AppLogger.error('   e possui o campo ios_public_api_key ou android_public_api_key');
      throw Exception('RevenueCat API key não encontrada no Firestore');
    }

    if (kReleaseMode && _isTestApiKey(apiKey)) {
      _disabledForRelease = true;
      _initialized = true;
      AppLogger.error('❌ RevenueCat: API key de TESTE em build RELEASE. Desativando compras.');
      return;
    }

    // 3. Configura o SDK
    final conf = PurchasesConfiguration(apiKey)
      ..entitlementVerificationMode = EntitlementVerificationMode.informational
      ..shouldShowInAppMessagesAutomatically = true;

    await Purchases.configure(conf);

    // 4. Listener oficial de mudanças
    Purchases.addCustomerInfoUpdateListener((info) {
      AppLogger.info('[RevenueCat] CustomerInfo listener acionado.');

      // Log detalhado das mudanças
      print('🔔 [RevenueCat] CustomerInfo atualizado via listener');
      print('   Entitlements ativos: ${info.entitlements.active.keys.toList()}');
      print('   Entitlements todos: ${info.entitlements.all.keys.toList()}');
      print('   Active subscriptions: ${info.activeSubscriptions}');
      print('   All purchased products: ${info.allPurchasedProductIdentifiers}');
      
      AppLogger.info('  - Entitlements ativos: ${info.entitlements.active.keys.toList()}');
      AppLogger.info('  - Entitlements todos: ${info.entitlements.all.keys.toList()}');
      AppLogger.info('  - Active subscriptions: ${info.activeSubscriptions}');
      AppLogger.info('  - All purchased products: ${info.allPurchasedProductIdentifiers}');

      _lastInfo = info;

      // notifica listeners locais
      for (final l in _listeners) {
        l(info);
      }
    });

    // 5. Carrega CustomerInfo inicial
    _lastInfo = await Purchases.getCustomerInfo();

    // Log detalhado dos entitlements iniciais
    print('🎫 [RevenueCat] CustomerInfo inicial carregado');
    print('   Entitlements ativos: ${_lastInfo!.entitlements.active.keys.toList()}');
    print('   Entitlements todos: ${_lastInfo!.entitlements.all.keys.toList()}');
    print('   Active subscriptions: ${_lastInfo!.activeSubscriptions}');
    print('   All purchased product IDs: ${_lastInfo!.allPurchasedProductIdentifiers}');
    
    AppLogger.info('RevenueCat: CustomerInfo inicial carregado');
    AppLogger.info('  - Entitlements ativos: ${_lastInfo!.entitlements.active.keys.toList()}');
    AppLogger.info('  - Entitlements todos: ${_lastInfo!.entitlements.all.keys.toList()}');
    AppLogger.info('  - Active subscriptions: ${_lastInfo!.activeSubscriptions}');
    AppLogger.info('  - All purchased products: ${_lastInfo!.allPurchasedProductIdentifiers}');

    // 6. Carrega e loga Offerings disponíveis
    try {
      print('\n🎁 [RevenueCat] Verificando offerings disponíveis...');
      final offerings = await Purchases.getOfferings();
      
      print('   📋 Offerings encontradas: ${offerings.all.keys.toList()}');
      print('   ⭐ Current offering: ${offerings.current?.identifier ?? "null"}');
      
      if (offerings.current != null) {
        print('   📦 Packages no current offering:');
        for (final pkg in offerings.current!.availablePackages) {
          print('      • ${pkg.identifier} (${pkg.packageType})');
          print('        Product: ${pkg.storeProduct.identifier}');
          print('        Price: ${pkg.storeProduct.priceString}');
        }
      } else {
        print('   ⚠️  Nenhuma current offering configurada');
      }
      
      if (offerings.all.isNotEmpty) {
        print('   📚 Todas as offerings:');
        for (final entry in offerings.all.entries) {
          print('      • ${entry.key}: ${entry.value.availablePackages.length} packages');
        }
      }
      
      AppLogger.info('Offerings verificadas: ${offerings.all.keys.toList()}');
    } catch (e) {
      print('   ⚠️  Erro ao verificar offerings: $e');
      AppLogger.warning('Erro ao verificar offerings na inicialização: $e');
    }

    _initialized = true;

    AppLogger.success('RevenueCat inicializado com sucesso.');
  }

  // --------------------------------------------------------------------------
  // PUBLIC LISTENERS
  // --------------------------------------------------------------------------
  static void addCustomerInfoUpdateListener(void Function(CustomerInfo) listener) {
    _listeners.add(listener);

    // notifica instantaneamente com o último CustomerInfo disponível
    if (_lastInfo != null) {
      listener(_lastInfo!);
    }
  }

  static void removeCustomerInfoUpdateListener(void Function(CustomerInfo) listener) {
    _listeners.remove(listener);
  }

  // --------------------------------------------------------------------------
  // OFFERINGS
  // --------------------------------------------------------------------------
  static Future<Offering?> getOffering() async {
    if (!_initialized) await initialize();

    try {
      final offerings = await Purchases.getOfferings();
      
      print('🔍 [RevenueCat] Buscando offerings...');
      print('   Offerings disponíveis: ${offerings.all.keys.toList()}');
      print('   Current offering: ${offerings.current?.identifier}');
      print('   _offeringId configurado: $_offeringId');
      
      AppLogger.info('RevenueCat: Buscando offerings...');
      AppLogger.info('  - Offerings disponíveis: ${offerings.all.keys.toList()}');
      AppLogger.info('  - Current offering: ${offerings.current?.identifier}');
      AppLogger.info('  - _offeringId configurado: $_offeringId');

      // tenta offering atual
      final current = offerings.current;
      if (current != null) {
        print('   ✅ Usando current offering com ${current.availablePackages.length} packages');
        AppLogger.info('  - Usando current offering com ${current.availablePackages.length} packages');
        for (final pkg in current.availablePackages) {
          print('      📦 ${pkg.identifier} | Type: ${pkg.packageType} | Product: ${pkg.storeProduct.identifier}');
          AppLogger.info('    Package: ${pkg.identifier} | Type: ${pkg.packageType} | Product: ${pkg.storeProduct.identifier}');
        }
        return current;
      }

      // fallback: offering configurado no Firestore
      if (_offeringId != null && offerings.all.containsKey(_offeringId)) {
        final offering = offerings.all[_offeringId]!;
        print('   ✅ Usando offering "$_offeringId" com ${offering.availablePackages.length} packages');
        AppLogger.info('  - Usando offering "$_offeringId" com ${offering.availablePackages.length} packages');
        for (final pkg in offering.availablePackages) {
          print('      📦 ${pkg.identifier} | Type: ${pkg.packageType} | Product: ${pkg.storeProduct.identifier}');
          AppLogger.info('    Package: ${pkg.identifier} | Type: ${pkg.packageType} | Product: ${pkg.storeProduct.identifier}');
        }
        return offering;
      }

      print('   ⚠️  Nenhuma offering encontrada!');
      AppLogger.warning('RevenueCat: Nenhuma offering encontrada!');
      return null;
    } catch (e) {
      print('   ❌ ERRO ao buscar offerings: $e');
      AppLogger.error('Erro ao buscar offerings: $e');
      
      if (e.toString().contains('CONFIGURATION_ERROR')) {
        print('   ');
        print('   ⚠️  ERRO DE CONFIGURAÇÃO NO REVENUECAT:');
        print('   - Verifique se os produtos estão configurados no RevenueCat Dashboard');
        print('   - Verifique se os produtos existem no App Store Connect');
        print('   - Verifique se o Bundle ID está correto');
        print('   - Para desenvolvimento iOS, configure um StoreKit Configuration File');
        print('   - Mais info: https://rev.cat/why-are-offerings-empty');
        print('   ');
      }
      
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // CUSTOMER INFO
  // --------------------------------------------------------------------------
  static Future<CustomerInfo> getCustomerInfo() async {
    if (!_initialized) await initialize();

    print('📥 [RevenueCat] Buscando CustomerInfo...');
    _lastInfo = await Purchases.getCustomerInfo();
    
    print('✅ [RevenueCat] CustomerInfo obtido com sucesso');
    print('   Entitlements ativos: ${_lastInfo!.entitlements.active.keys.toList()}');
    print('   Entitlements todos: ${_lastInfo!.entitlements.all.keys.toList()}');
    print('   Active subscriptions: ${_lastInfo!.activeSubscriptions}');
    print('   All purchased products: ${_lastInfo!.allPurchasedProductIdentifiers}');
    
    // Log detalhado de cada entitlement ativo
    for (final entKey in _lastInfo!.entitlements.active.keys) {
      final ent = _lastInfo!.entitlements.active[entKey]!;
      print('   📋 Entitlement "$entKey":');
      print('      - isActive: ${ent.isActive}');
      print('      - willRenew: ${ent.willRenew}');
      print('      - periodType: ${ent.periodType}');
      print('      - productIdentifier: ${ent.productIdentifier}');
      print('      - expirationDate: ${ent.expirationDate}');
      print('      - billingIssue: ${ent.billingIssueDetectedAt != null}');
    }
    
    AppLogger.info('CustomerInfo obtido: ${_lastInfo!.entitlements.active.keys.toList()}');
    return _lastInfo!;
  }

  // --------------------------------------------------------------------------
  // HAS ACCESS (usado externamente pelo Provider/Monitoring)
  // --------------------------------------------------------------------------
  static bool hasAccess(CustomerInfo info) {
    try {
      final entId = _entitlementId ?? REVENUE_CAT_ENTITLEMENT_ID;
      
      print('🔍 [RevenueCat] Verificando acesso ao entitlement: "$entId"');
      print('   📋 Entitlements ativos disponíveis: ${info.entitlements.active.keys.toList()}');
      print('   📋 Todos entitlements: ${info.entitlements.all.keys.toList()}');
      
      final ent = info.entitlements.active[entId];

      if (ent == null) {
        print('   ❌ Entitlement "$entId" NÃO encontrado nos ativos');
        
        // Verifica se existe em 'all' mas não está ativo
        final entAll = info.entitlements.all[entId];
        if (entAll != null) {
          print('   ⚠️  Entitlement existe em "all" mas não está ativo');
          print('       - isActive: ${entAll.isActive}');
          print('       - expirationDate: ${entAll.expirationDate}');
          print('       - productIdentifier: ${entAll.productIdentifier}');
        }
        
        return false;
      }
      
      // Log apenas quando encontrar assinatura ativa
      print('✅ [RevenueCat] Assinatura "$entId" ativa');
      print('   - willRenew: ${ent.willRenew}');
      print('   - expirationDate: ${ent.expirationDate}');
      print('   - billingIssue: ${ent.billingIssueDetectedAt != null}');

      // billing issue → sem acesso
      if (ent.billingIssueDetectedAt != null) return false;

      // expiração com margem de tolerância de 5 minutos
      // Isso evita problemas de sincronização de relógio
      if (ent.expirationDate != null) {
        final exp = DateTime.parse(ent.expirationDate!);
        final now = DateTime.now();
        // Adiciona 5 minutos de margem para evitar rejeições por diferença de relógio
        final expWithMargin = exp.add(const Duration(minutes: 5));
        if (expWithMargin.isBefore(now)) return false;
      }

      // se isActive = true → acesso OK
      final hasAccess = ent.isActive;
      print('   🎫 Resultado hasAccess: $hasAccess');
      return hasAccess;
    } catch (e) {
      print('   ❌ Erro ao verificar acesso: $e');
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // COMPRAR
  // --------------------------------------------------------------------------
  static Future<CustomerInfo> purchasePackage(Package package) async {
    if (!_initialized) await initialize();
    if (_disabledForRelease) {
      throw Exception('RevenueCat desativado: API key de teste em release');
    }

    print('💳 [RevenueCat] Iniciando compra');
    print('   Package identifier: ${package.identifier}');
    print('   Package type: ${package.packageType}');
    print('   Product ID: ${package.storeProduct.identifier}');
    print('   Product title: ${package.storeProduct.title}');
    print('   Product price: ${package.storeProduct.priceString}');
    print('   ⚠️  ATENÇÃO: Este ID deve existir no Google Play Console!');
    print('   ⚠️  Verifique se "${package.storeProduct.identifier}" está cadastrado e ATIVO');
    
    AppLogger.info('Iniciando compra: ${package.storeProduct.identifier}');
    
    try {
      if (Platform.isAndroid) {
        final canPay = await Purchases.canMakePayments();
        if (!canPay) {
          throw Exception('Billing indisponível neste dispositivo');
        }
      }

      if (package.storeProduct.identifier.trim().isEmpty) {
        throw Exception('Produto inválido para compra (identifier vazio)');
      }

      final result = await Purchases.purchasePackage(package);

      print('✅ [RevenueCat] Compra concluída com sucesso!');
      print('   Entitlements ativos após compra: ${result.customerInfo.entitlements.active.keys.toList()}');
      print('   Active subscriptions: ${result.customerInfo.activeSubscriptions}');
      print('   All purchased products: ${result.customerInfo.allPurchasedProductIdentifiers}');
      
      AppLogger.success('Compra concluída!');
      AppLogger.info('  - Entitlements ativos: ${result.customerInfo.entitlements.active.keys.toList()}');
      AppLogger.info('  - Active subscriptions: ${result.customerInfo.activeSubscriptions}');

      _lastInfo = result.customerInfo;

      return result.customerInfo;
    } catch (e) {
      print('❌ [RevenueCat] Erro na compra: $e');
      AppLogger.error('Erro na compra: $e');
      
      if (e is PlatformException) {
        print('   PlatformException code: ${e.code}');
        print('   PlatformException message: ${e.message}');
        print('   PlatformException details: ${e.details}');
      }
      
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // RESTORE
  // --------------------------------------------------------------------------
  static Future<CustomerInfo> restorePurchases() async {
    if (!_initialized) await initialize();
    if (_disabledForRelease) {
      throw Exception('RevenueCat desativado: API key de teste em release');
    }

    print('🔄 [RevenueCat] Restaurando compras...');
    final info = await Purchases.restorePurchases();
    
    print('✅ [RevenueCat] Compras restauradas!');
    print('   Entitlements ativos: ${info.entitlements.active.keys.toList()}');
    print('   Active subscriptions: ${info.activeSubscriptions}');
    print('   All purchased products: ${info.allPurchasedProductIdentifiers}');
    
    AppLogger.success('Compras restauradas!');
    AppLogger.info('  - Entitlements ativos: ${info.entitlements.active.keys.toList()}');
    AppLogger.info('  - Active subscriptions: ${info.activeSubscriptions}');
    
    _lastInfo = info;
    return info;
  }

  // --------------------------------------------------------------------------
  // LOGIN / LOGOUT
  // --------------------------------------------------------------------------
  static Future<void> login(String userId) async {
    if (!_initialized) await initialize();
    if (_disabledForRelease) {
      AppLogger.warning('RevenueCat desativado: login ignorado (API key de teste em release).');
      return;
    }
    
    // Idempotency check: se já estamos logados com este ID, não faz nada
    if (_currentRcUserId == userId) {
      AppLogger.info('RevenueCat: Já logado como $userId. Ignorando login redundante.');
      return;
    }

    await Purchases.logIn(userId);
    _currentRcUserId = userId;
    _lastInfo = await Purchases.getCustomerInfo();
  }

  static Future<void> logout() async {
    if (!_initialized || _disabledForRelease) return;
    await Purchases.logOut();
    _currentRcUserId = null;
    _lastInfo = null;
  }

  // --------------------------------------------------------------------------
  // FIRESTORE CONFIG
  // --------------------------------------------------------------------------
  static Future<String?> _getApiKey() async {
    try {
      print('🔍 [RevenueCat] Buscando API key do Firestore...');
      print('   Collection: $C_APP_INFO');
      print('   Document: revenue_cat');
      print('   Platform: ${Platform.isIOS ? "iOS" : Platform.isAndroid ? "Android" : "Outro"}');
      
      AppLogger.info('RevenueCat: Buscando API key do Firestore...');
      AppLogger.info('  - Collection: $C_APP_INFO');
      AppLogger.info('  - Document: revenue_cat');
      AppLogger.info('  - Platform: ${Platform.isIOS ? "iOS" : Platform.isAndroid ? "Android" : "Outro"}');
      
      final snap = await FirebaseFirestore.instance
          .collection(C_APP_INFO)
          .doc('revenue_cat')
          .get();

      print('   Document exists: ${snap.exists}');
      AppLogger.info('  - Document exists: ${snap.exists}');
      
      final data = snap.data();
      if (data == null) {
        print('   ❌ Data é null!');
        AppLogger.warning('  - Data é null!');
        return null;
      }

      print('   Keys disponíveis: ${data.keys.toList()}');
      AppLogger.info('  - Keys disponíveis: ${data.keys.toList()}');

      String? apiKey;
      if (Platform.isAndroid) {
        apiKey = data['android_public_api_key'];
        print('   Buscando android_public_api_key: ${apiKey != null ? "✅ encontrada" : "❌ não encontrada"}');
        AppLogger.info('  - Buscando android_public_api_key: ${apiKey != null ? "encontrada" : "não encontrada"}');
      } else if (Platform.isIOS) {
        apiKey = data['ios_public_api_key'];
        print('   Buscando ios_public_api_key: ${apiKey != null ? "✅ encontrada" : "❌ não encontrada"}');
        AppLogger.info('  - Buscando ios_public_api_key: ${apiKey != null ? "encontrada" : "não encontrada"}');
      } else {
        apiKey = data['public_api_key'];
        print('   Buscando public_api_key: ${apiKey != null ? "✅ encontrada" : "❌ não encontrada"}');
        AppLogger.info('  - Buscando public_api_key: ${apiKey != null ? "encontrada" : "não encontrada"}');
      }

      print('   🔑 API Key resultado: ${apiKey != null ? "encontrada (${apiKey.length} chars)" : "NULL"}');
      return apiKey;
    } catch (e) {
      print('   ❌ ERRO ao buscar API key: $e');
      AppLogger.error('Erro ao buscar API key: $e');
      return null;
    }
  }

  static bool _isTestApiKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized.contains('test') ||
        normalized.contains('sandbox') ||
        normalized.contains('dev');
  }

  static Future<void> _loadConfiguration() async {
    try {
      print('⚙️ [RevenueCat] Carregando configuração do Firestore...');
      AppLogger.info('RevenueCat: Carregando configuração...');
      
      final doc = await FirebaseFirestore.instance
          .collection(C_APP_INFO)
          .doc('revenue_cat')
          .get();

      final data = doc.data();
      if (data == null) {
        print('   ⚠️  Config data é null, usando defaults');
        print('   📋 Default Entitlement ID: $REVENUE_CAT_ENTITLEMENT_ID');
        print('   📋 Default Offering ID: $REVENUE_CAT_OFFERINGS_ID');
        AppLogger.warning('  - Config data é null, usando defaults');
        _entitlementId = REVENUE_CAT_ENTITLEMENT_ID;
        return;
      }

      print('   📄 Documento revenue_cat encontrado');
      print('   🔑 Keys disponíveis: ${data.keys.toList()}');

      final ent = data['REVENUE_CAT_ENTITLEMENT_ID'];
      final off = data['REVENUE_CAT_OFFERINGS_ID'];

      print('   📋 Valor no Firestore - REVENUE_CAT_ENTITLEMENT_ID: $ent');
      print('   📋 Valor no Firestore - REVENUE_CAT_OFFERINGS_ID: $off');

      _entitlementId = (ent is String && ent.isNotEmpty)
          ? ent
          : REVENUE_CAT_ENTITLEMENT_ID;

      _offeringId = (off is String && off.isNotEmpty)
          ? off
          : REVENUE_CAT_OFFERINGS_ID;

    print('   ✅ Entitlement ID final: $_entitlementId');
    print('   ✅ Offering ID final: $_offeringId');
    
    print('\n⚠️  IMPORTANTE: Verifique no RevenueCat Dashboard:');
    print('   1. O entitlement "$_entitlementId" está configurado');
    print('   2. Os produtos Android estão vinculados ao entitlement');
    print('   3. Formato dos produtos: 01_semanal:semanal, 01_semanal:mensal, 01_semanal:anual');

    AppLogger.info('  - Entitlement ID: $_entitlementId');
    AppLogger.info('  - Offering ID: $_offeringId');    } catch (e) {
      print('   ❌ ERRO ao carregar configuração: $e');
      AppLogger.error('Erro ao carregar configuração: $e');
      _entitlementId = REVENUE_CAT_ENTITLEMENT_ID;
    }
  }

  // --------------------------------------------------------------------------
  // MÉTODOS AUXILIARES PARA COMPATIBILIDADE
  // --------------------------------------------------------------------------
  
  /// Getter público para último CustomerInfo
  static CustomerInfo? get lastCustomerInfo => _lastInfo;

  /// Aguarda SDK estar pronto (compatibilidade)
  static Future<void> awaitReady({Duration timeout = const Duration(seconds: 5)}) async {
    if (_initialized) return;
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Garante que SDK está configurado (compatibilidade)
  static Future<bool> ensureConfigured() async {
    if (!_initialized) {
      await initialize();
    }
    return _initialized;
  }

  /// Inicia refresh periódico (compatibilidade - não faz nada na versão simplificada)
  static void startPeriodicRefresh({Duration? interval}) {
    // Versão simplificada não usa refresh periódico
    AppLogger.info('startPeriodicRefresh: ignorado (versão simplificada)');
  }

  /// Logs de diagnóstico seguros para getCustomerInfo (compatibilidade)
  static Future<void> getCustomerInfoSafeLog() async {
    try {
      await getCustomerInfo();
    } catch (e) {
      AppLogger.info('getCustomerInfoSafeLog: erro ignorado ($e)');
    }
  }
}
