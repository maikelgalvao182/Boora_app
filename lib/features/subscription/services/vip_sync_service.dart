import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:partiu/features/subscription/services/subscription_monitoring_service.dart';

/// VipSyncService
///
/// Objetivo: reduzir a latência entre o momento em que o RevenueCat confirma o
/// entitlement (client-side) e o momento em que o Firestore passa a permitir
/// leituras VIP (server-side).
///
/// Como funciona:
/// - Observa mudanças reais de VIP via [SubscriptionMonitoringService]
/// - Quando detecta transição false -> true, chama a callable `syncVipNow`
/// - A callable atualiza Users/{uid} com base no SubscriptionStatus (escrito pelo webhook)
///
/// Importante: não substitui o webhook. É um "kick" para acelerar.
class VipSyncService {
  VipSyncService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  bool _started = false;
  bool _lastVip = false;

  Timer? _cooldownTimer;
  bool _cooldownActive = false;

  /// Inicia a escuta (idempotente).
  void start() {
    if (_started) return;
    _started = true;

    _lastVip = SubscriptionMonitoringService.hasVipAccess;

    SubscriptionMonitoringService.addVipListener(_onVipChanged);
  }

  void dispose() {
    _cooldownTimer?.cancel();
    // Não temos removeVipListener no MonitoringService por "token".
    // Como o service é pensado como singleton de App-lifecycle, mantemos simples.
  }

  void _onVipChanged(bool isVip) {
    // Queremos apenas o momento da ativação.
    final becameVip = !_lastVip && isVip;
    _lastVip = isVip;

    if (!becameVip) return;

    // Evita spam em múltiplos updates (ou múltiplas telas registrando listener).
    if (_cooldownActive) {
      debugPrint('[VipSyncService] Ignorando sync (cooldown ativo)');
      return;
    }

    _cooldownActive = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(seconds: 20), () {
      _cooldownActive = false;
    });

    unawaited(_syncNow());
  }

  Future<void> _syncNow() async {
    try {
      debugPrint('[VipSyncService] Chamando callable syncVipNow...');

      final callable = _functions.httpsCallable(
        'syncVipNow',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );

      final result = await callable.call<Map<String, dynamic>>({});
      debugPrint('[VipSyncService] syncVipNow ok: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[VipSyncService] FirebaseFunctionsException: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('[VipSyncService] Erro inesperado: $e');
    }
  }
}
