// Imports dos módulos criados
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/subscription/domain/subscription_plan.dart';
import 'package:partiu/features/subscription/presentation/controllers/subscription_purchase_controller.dart';
import 'package:partiu/features/subscription/presentation/widgets/subscription_benefits_list.dart';
import 'package:partiu/features/subscription/presentation/widgets/subscription_footer.dart';
import 'package:partiu/features/subscription/presentation/widgets/subscription_header.dart';
import 'package:partiu/features/subscription/presentation/widgets/subscription_plan_card.dart';
import 'package:partiu/features/subscription/presentation/widgets/subscription_states.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/toast_messages_helper.dart';
import 'package:partiu/features/subscription/providers/simple_subscription_provider.dart';
import 'package:partiu/features/subscription/services/simple_revenue_cat_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Dialog de assinatura VIP - Versão Modularizada
/// 
/// Responsabilidades:
/// - Orquestrar widgets modulares
/// - Gerenciar estado do dialog
/// - Responder a mudanças de assinatura
class VipBottomSheet extends StatefulWidget {
  const VipBottomSheet({super.key});

  @override
  State<VipBottomSheet> createState() => _VipBottomSheetState();
}

class _VipBottomSheetState extends State<VipBottomSheet> {
  late final SubscriptionPurchaseController _controller;
  bool _isInitialized = false;
  bool _hasClosed = false;

  void _closeIfNeeded() {
    if (!mounted || _hasClosed) return;
    _hasClosed = true;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }
  
  // Listener de acesso VIP (via SubscriptionMonitoringService)
  void _onVipAccessChanged(bool hasAccess) {
    if (!mounted) return;
    // Fecha imediatamente quando o RevenueCat confirma acesso,
    // evitando ficar “preso” aguardando a sync do Firestore.
    if (hasAccess) {
      _closeIfNeeded();
    }
  }

  // Listener para mudanças no usuário (Firestore)
  void _onUserChanged() {
    if (!mounted) return;
    final user = AppState.currentUser.value;
    // Só fecha se o Firestore confirmar o VIP (vipExpiresAt válido)
    if (user != null && user.hasActiveVip) {
      _closeIfNeeded();
    }
  }

  @override
  void initState() {
    super.initState();

    // Monitora mudanças no usuário (Firestore)
    AppState.currentUser.addListener(_onUserChanged);

    // Inicializa controller (seguro usar read em initState)
    final simpleProvider = context.read<SimpleSubscriptionProvider>();
    _controller = SubscriptionPurchaseController(
      provider: simpleProvider,
      onSuccess: _handleSuccess,
      onError: _handleError,
    );

    // Aguarda build completar para iniciar carregamento
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Observa mudanças de acesso VIP globalmente (sem Consumer)
      VipAccessService.addAccessListener(_onVipAccessChanged);

      // Garante que provider está inicializado
      if (!simpleProvider.isInitialized) {
        await simpleProvider.init();
      }

      // Verifica se já tem acesso via Firestore (Fonte da Verdade)
      if (mounted) {
        final user = AppState.currentUser.value;
        if (user != null && user.hasActiveVip) {
          Navigator.of(context).pop(true);
          return;
        }
      }

      // Carrega planos
      if (!mounted) return;
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    });
  }

  @override
  void dispose() {
    AppState.currentUser.removeListener(_onUserChanged);
    // Remove listener de acesso VIP
    VipAccessService.removeAccessListener(_onVipAccessChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Trata sucesso na compra/restore
  void _handleSuccess() {
    if (!mounted) return;

    final tm = ToastMessagesHelper(context);
    ToastService.showSuccess(
      message: tm.vipSubscriptionRestored,
    );

    // Se o RevenueCat já confirmou acesso, fecha na hora.
    final customerInfo = SimpleRevenueCatService.lastCustomerInfo;
    final hasVipAccess = customerInfo != null &&
        SimpleRevenueCatService.hasAccess(customerInfo);
    if (hasVipAccess) {
      _closeIfNeeded();
      return;
    }

    // Não fecha imediatamente. Aguarda sincronização com Firestore.
    // O listener _onUserChanged fechará o dialog quando o vipExpiresAt for atualizado.
    ToastService.showInfo(
      message: AppLocalizations.of(context).translate('syncing_subscription'),
    );
  }

  /// Trata erro na compra/restore
  void _handleError(String error) {
    if (!mounted) return;

    final tm = ToastMessagesHelper(context);

    if (error.contains('cancelled')) {
      ToastService.showInfo(
        message: '${tm.paymentCancelled}: ${tm.paymentCancelledByUser}',
      );
    } else if (error.contains('No previous')) {
      ToastService.showError(
        message: '${tm.error}: ${AppLocalizations.of(context).translate('no_previous_purchase_found')}',
      );
    } else {
      ToastService.showError(
        message: '${tm.error}: $error',
      );
    }
  }

  /// Trata restore de compras
  Future<void> _handleRestore() async {
    if (!mounted) return;

    ToastService.showInfo(
      message: AppLocalizations.of(context).translate('processing'),
    );

    await _controller.restorePurchases();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    // Sem Consumer: animação e UI reagem ao controller/listeners locais
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildDialogContent(i18n),
    );
  }

  /// Constrói conteúdo principal do dialog
  Widget _buildDialogContent(AppLocalizations i18n) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SubscriptionHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        if (!_isInitialized || _controller.isLoading)
                          const SubscriptionLoadingState()
                        else if (_controller.error != null)
                          SubscriptionErrorState(
                            error: _controller.error!,
                            onRetry: () => _controller.retry(),
                          )
                        else if (!_controller.hasPlans)
                          const SubscriptionEmptyState()
                        else
                          _buildPlansSection(i18n),
                    ],
                  ),
                  const SubscriptionBenefitsList(),
                ],
              ),
            ),
          ),
          
          // Botão de compra e footer movidos para o final
          Column(
            children: [
              _buildPurchaseButton(i18n),
              SubscriptionFooter(
                onRestore: _handleRestore,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Constrói seção de planos
  Widget _buildPlansSection(AppLocalizations i18n) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Card plano semanal (se disponível)
              if (_controller.weeklyPackage != null)
                Expanded(
                  child: SubscriptionPlanCard(
                    package: _controller.weeklyPackage!,
                    isSelected: _controller.selectedPlan == SubscriptionPlan.weekly,
                    onTap: () => _controller.selectPlan(SubscriptionPlan.weekly),
                  ),
                ),

              if (_controller.weeklyPackage != null && _controller.monthlyPackage != null)
                const SizedBox(width: 8),

              // Card plano mensal (se disponível)
              if (_controller.monthlyPackage != null)
                Expanded(
                  child: SubscriptionPlanCard(
                    package: _controller.monthlyPackage!,
                    isSelected: _controller.selectedPlan == SubscriptionPlan.monthly,
                    onTap: () => _controller.selectPlan(SubscriptionPlan.monthly),
                  ),
                ),

              if (_controller.monthlyPackage != null && _controller.annualPackage != null)
                const SizedBox(width: 8),

              // Card plano anual (se disponível)
              if (_controller.annualPackage != null)
                Expanded(
                  child: SubscriptionPlanCard(
                    package: _controller.annualPackage!,
                    isSelected: _controller.selectedPlan == SubscriptionPlan.annual,
                    onTap: () => _controller.selectPlan(SubscriptionPlan.annual),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Constrói botão de compra
  Widget _buildPurchaseButton(AppLocalizations i18n) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isPurchasing = _controller.isPurchasing;
        final selectedPlan = _controller.selectedPlan;

        final buttonText = switch (selectedPlan) {
          SubscriptionPlan.weekly => i18n.translate('subscribe_weekly_plan'),
          SubscriptionPlan.monthly => i18n.translate('subscribe_monthly_plan'),
          SubscriptionPlan.annual => i18n.translate('subscribe_annual_plan'),
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: GlimpseButton(
            text: buttonText,
            backgroundColor: GlimpseColors.primary,
            isProcessing: isPurchasing,
            onPressed: isPurchasing ? null : _controller.purchaseSelected,
          ),
        );
      },
    );
  }
}
