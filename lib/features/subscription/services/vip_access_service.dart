import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/dialogs/vip_dialog.dart';
import 'package:partiu/features/subscription/services/simple_revenue_cat_service.dart';
import 'package:partiu/features/subscription/services/subscription_monitoring_service.dart';
import 'package:flutter/material.dart';

/// Serviço para verificar status VIP e controlar acesso a funcionalidades premium
/// IMPORTANTE: Não usa cache próprio, confia 100% no SubscriptionMonitoringService
class VipAccessService {
  /// Ativa/desativa verbosidade de logs (pode ser mudado em runtime se necessário)
  static bool verbose = true;

  static void _log(String msg, {String? traceId}) {
    if (!verbose) return;
    // Log message (timestamp not needed for this implementation)
  }
  
  /// Limpa o cache (mantido para compatibilidade, mas não faz nada)
  @Deprecated('VipAccessService não usa mais cache próprio')
  static void clearCache() {
    // Método vazio mantido para compatibilidade com código existente
    // Não imprime nada para evitar poluir os logs
  }

  /// Inicializa o serviço VIP
  static Future<void> initialize() async {
    try {
  // Aguarda RevenueCat pronto para evitar chamadas precoces
  await SimpleRevenueCatService.awaitReady();
      // Inicializa o serviço de monitoramento em tempo real
      await SubscriptionMonitoringService.initialize();
      
      
      // Adiciona listener para mudanças de status (sem log desnecessário)
      SubscriptionMonitoringService.addVipListener((hasAccess) {
        // Status mudou, cache é limpo automaticamente no SubscriptionMonitoringService
      });
      
    } catch (e) {
      // Ignore initialization errors
    }
  }

  /// Realiza verificação inicial do status VIP sem mostrar dialog
  /// Útil para pré-carregar o status ao iniciar o app
  static Future<bool> checkInitialStatus() async {
    try {
  await SimpleRevenueCatService.awaitReady();
      // Força verificação via monitoramento
      await SubscriptionMonitoringService.refresh();
      final hasAccess = SubscriptionMonitoringService.hasVipAccess;
      
      return hasAccess;
    } catch (e) {
      return false;
    }
  }

  /// Verificação híbrida: combina dados do Firestore com monitoramento em tempo real
  /// Usa o serviço de monitoramento para detectar mudanças automaticamente
  static Future<bool> hasVipAccess(BuildContext context, {String? traceId, String? source}) async {
    _log('→ hasVipAccess (RevenueCat only) source=${source ?? 'unspecified'}', traceId: traceId);
    
    try {
  await SimpleRevenueCatService.awaitReady();
      // Verificação via monitoramento em tempo real (RevenueCat)
      final realtimeAccess = SubscriptionMonitoringService.hasVipAccess;
      _log('Status RevenueCat: $realtimeAccess', traceId: traceId);
      
      return realtimeAccess;
      
    } catch (e) {
      _log('ERRO em hasVipAccess: $e', traceId: traceId);
      
      // Fallback: usa apenas o monitoramento em tempo real
      return SubscriptionMonitoringService.hasVipAccess;
    }
  }

  /// Adiciona um listener para mudanças no status VIP
  static void addAccessListener(void Function(bool) listener) {
    SubscriptionMonitoringService.addVipListener(listener);
  }

  /// Remove um listener de mudanças no status VIP
  static void removeAccessListener(void Function(bool) listener) {
    SubscriptionMonitoringService.removeVipListener(listener);
  }

  /// Força verificação manual imediata
  static Future<void> forceCheck() async {
    await SubscriptionMonitoringService.refresh();
  }

  /// Verifica o acesso ou mostra o diálogo VIP
  /// IMPORTANTE: Verifica Firestore (User.hasActiveVip) E RevenueCat
  static Future<bool> checkAccessOrShowDialog(BuildContext context, {String? source}) async {
    _log('→ checkAccessOrShowDialog source=${source ?? 'unspecified'}');
    
    try {
      // 1. Verifica Firestore (Fonte da Verdade)
      final user = AppState.currentUser.value;
      final firestoreAccess = user?.hasActiveVip ?? false;
      
      if (firestoreAccess) {
        _log('✅ Acesso VIP confirmado pelo Firestore');
        return true;
      }

      // 2. Se não tem no Firestore, BLOQUEIA.
      // Motivo: Se liberarmos baseado apenas no RevenueCat (client-side),
      // o Firestore (server-side) vai bloquear a leitura dos dados e dar erro de permissão.
      // É melhor mostrar o dialog do que uma tela de erro.
      
      // 3. Sem acesso em lugar nenhum -> Mostra Dialog
      _log('❌ Sem acesso VIP (Firestore), mostrando dialog');
      if (!context.mounted) return false;
      
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.90,
          child: const VipBottomSheet(),
        ),
      );
      
      return result ?? false;
      
    } catch (e) {
      _log('Erro em checkAccessOrShowDialog: $e');
      if (!context.mounted) return false;
      return false;
    }
  }
}
