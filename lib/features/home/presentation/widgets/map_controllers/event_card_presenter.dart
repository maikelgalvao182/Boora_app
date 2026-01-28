import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/screens/chat/chat_screen_refactored.dart';
import 'package:partiu/shared/widgets/confetti_celebration.dart';

import 'package:partiu/features/home/presentation/coordinators/home_tab_coordinator.dart';
import 'package:partiu/features/home/presentation/coordinators/home_navigation_coordinator.dart';

class EventCardPresenter {
  final MapViewModel viewModel;
  
  bool isEventCardOpen = false;

  EventCardPresenter({required this.viewModel});

  void dismissEventCardIfOpen(BuildContext context) {
    if (!isEventCardOpen) return;
    Navigator.of(context).pop();
  }

  void showClusterEventsSheet(BuildContext context, List<EventModel> events, Function(EventModel) onEventTap) {
    final sorted = [...events]
      ..sort((a, b) => (a.title).toLowerCase().compareTo((b.title).toLowerCase()));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Eventos neste cluster (${sorted.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = sorted[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(e.emoji, style: const TextStyle(fontSize: 20)),
                        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: e.category == null
                            ? null
                            : Text(e.category!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.of(context).pop();
                          onEventTap(e);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> onMarkerTap(BuildContext context, EventModel event, {bool showConfetti = false}) async {
    debugPrint('🔴🔴🔴 EventCardPresenter.onMarkerTap CHAMADO! 🔴🔴🔴');
    debugPrint('🔴 Called for: ${event.id} - ${event.title}');

    // [FIX] Guardrail: EventCard só deve abrir se estivermos na Tab do Mapa (index 0)
    // Se não estivermos, redirecionamos para o fluxo correto via Coordinator.
    if (HomeTabCoordinator.instance.currentIndex != 0) {
      debugPrint('⚠️ [EventCardPresenter] Chamado fora da Tab 0 (Mapa). Redirecionando para HomeNavigationCoordinator...');
      HomeNavigationCoordinator.instance.openEventOnMap(event.id);
      return;
    }

    if (isEventCardOpen) {
      debugPrint('⚠️ EventCard já aberto - ignorando novo tap');
      return;
    }
    isEventCardOpen = true;
    
    // ✅ BUSCAR EVENTO ATUALIZADO da lista do ViewModel
    EventModel enrichedEvent = event;
    try {
      final updated = viewModel.events.firstWhere((e) => e.id == event.id);
      enrichedEvent = updated;
      debugPrint('✅ Evento atualizado encontrado na lista do ViewModel');
    } catch (_) {
      debugPrint('⚠️ Evento não encontrado na lista, usando cópia do marker');
    }
    
    final controller = EventCardController(
      eventId: enrichedEvent.id,
      preloadedEvent: enrichedEvent,
      mapViewModel: viewModel, // ✅ INJETANDO VIEWMODEL
    );
    
    if (showConfetti) {
      ConfettiOverlay.show(context);
    }
    
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      constraints: const BoxConstraints(
        maxWidth: 500,
      ),
      builder: (sheetContext) => EventCard(
        controller: controller,
        onActionPressed: () async {
          final navigator = Navigator.of(sheetContext);
          navigator.pop();

          if (controller.isCreator || controller.isApproved) {
            _navigateToChat(context, event);
          }
        },
      ),
    ).whenComplete(() {
      controller.dispose();
      isEventCardOpen = false;
      debugPrint('🔴 EventCard fechado via whenComplete');
    });
  }

  void _navigateToChat(BuildContext context, EventModel event) {
    final eventName = event.title;
    final emoji = event.emoji;

    final chatUser = app_user.User.fromDocument({
      'userId': 'event_${event.id}',
      'fullName': eventName,
      'photoUrl': emoji,
      'gender': '',
      'birthDay': 1,
      'birthMonth': 1,
      'birthYear': 2000,
      'jobTitle': '',
      'bio': '',
      'country': '',
      'locality': '',
      'latitude': 0.0,
      'longitude': 0.0,
      'status': 'active',
      'level': '',
      'isVerified': false,
      'registrationDate': DateTime.now().toIso8601String(),
      'lastLoginDate': DateTime.now().toIso8601String(),
      'totalLikes': 0,
      'totalVisits': 0,
      'isOnline': false,
    });

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isNotEmpty &&
        BlockService().isBlockedCached(currentUserId, event.createdBy)) {
      final i18n = AppLocalizations.of(context);
      ToastService.showWarning(
        message: i18n.translate('user_blocked_cannot_message'),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreenRefactored(
          user: chatUser,
          isEvent: true,
          eventId: event.id,
        ),
      ),
    );
  }
}
