import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/notifications/controllers/simplified_notification_controller.dart';
import 'package:partiu/features/notifications/widgets/notification_item_widget.dart';
import 'package:partiu/features/notifications/widgets/notification_horizontal_filters.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/infinite_list_view.dart';
import 'package:partiu/widgets/skeletons/notification_list_skeleton.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// [MVVM] Constantes da View - evita magic numbers
class _NotificationScreenConstants {
  static const int filterCount = 5; // All, Activities, Profile Views, Reviews, Followers
  static const double loadingIndicatorPadding = 16;
}

/// SIMPLIFIED NOTIFICATION SCREEN
/// Baseado no padrão Chatter: simples, direto e eficaz
/// 
/// Arquitetura MVVM:
/// - View: Este widget (apenas renderização e eventos)
/// - ViewModel: SimplifiedNotificationController (lógica e estado)
/// - Model: NotificationsRepository (dados)
/// 
/// Características:
/// - Widget único com RefreshIndicator
/// - Lista simples com scroll infinito
/// - Controller gerencia todo o estado
class SimplifiedNotificationScreen extends StatefulWidget {
  const SimplifiedNotificationScreen({
    required this.controller,
    super.key,
    this.onBackPressed,
  });
  
  final SimplifiedNotificationController controller;
  final VoidCallback? onBackPressed;

  @override
  State<SimplifiedNotificationScreen> createState() => _SimplifiedNotificationScreenState();
}

class _SimplifiedNotificationScreenState extends State<SimplifiedNotificationScreen> {
  // [PERF] Cache de páginas de filtro para evitar List.generate em cada build
  late final List<Widget> _filterPages = List.generate(
    _NotificationScreenConstants.filterCount,
    (index) => _NotificationFilterPage(
      key: ValueKey('filter_page_$index'),
      filterIndex: index,
      controller: widget.controller,
    ),
    growable: false,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Inicializa controller (sem VIP check)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.initialize(true); // isVip sempre true no Partiu
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final bgColor = GlimpseColors.bgColorLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: GlimpseAppBar(
        title: i18n.translate('notifications'),
        onBack: widget.onBackPressed ?? () => Navigator.pop(context),
        onAction: () => _showDeleteConfirmation(context, i18n),
        actionText: i18n.translate('clear'),
      ),
      body: Column(
        children: [
          // Filtros horizontais
          _FilterSection(
            controller: widget.controller,
            i18n: i18n,
          ),
          
          // [PERF] IndexedStack com páginas cacheadas
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                return IndexedStack(
                  index: widget.controller.selectedFilterIndex,
                  sizing: StackFit.expand,
                  children: _filterPages,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context, AppLocalizations i18n) async {
    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('delete_notifications'),
      message: i18n.translate('all_notifications_will_be_deleted'),
      destructiveText: i18n.translate('DELETE'),
      cancelText: i18n.translate('CANCEL'),
    );

    if (confirmed == true && context.mounted) {
      await widget.controller.deleteAllNotifications();
    }
  }
}

/// [PERF] Widget de seção de filtros otimizado
class _FilterSection extends StatefulWidget {
  const _FilterSection({
    required this.controller,
    required this.i18n,
  });
  
  final SimplifiedNotificationController controller;
  final AppLocalizations i18n;

  @override
  State<_FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends State<_FilterSection> {
  late final List<String> _filterLabels;

  @override
  void initState() {
    super.initState();
    _filterLabels = SimplifiedNotificationController.filterLabelKeys
        .map((key) => widget.i18n.translate(key))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.controller.selectedFilterIndexNotifier,
      builder: (context, selectedIndex, _) {
        return NotificationHorizontalFilters(
          items: _filterLabels,
          selectedIndex: selectedIndex,
          onSelected: widget.controller.setFilter,
        );
      },
    );
  }
}

/// Widget de página de filtro
class _NotificationFilterPage extends StatefulWidget {
  const _NotificationFilterPage({
    required this.filterIndex,
    required this.controller,
    super.key,
  });
  
  final int filterIndex;
  final SimplifiedNotificationController controller;

  @override
  State<_NotificationFilterPage> createState() => _NotificationFilterPageState();
}

class _NotificationFilterPageState extends State<_NotificationFilterPage> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final i18n = AppLocalizations.of(context);
    final filterKey = widget.controller.mapFilterIndexToKey(widget.filterIndex);
    
    return ValueListenableBuilder<int>(
      valueListenable: widget.controller.getFilterNotifier(filterKey),
      builder: (context, updateCount, _) {
        final notifications = widget.controller.getNotificationsForFilter(filterKey);
        final hasMore = widget.controller.hasMoreForFilter(filterKey);
        final isLoading = widget.controller.isLoading && 
                         widget.controller.selectedFilterKey == filterKey;
        final errorMessage = widget.controller.errorMessage;
        final isFirstLoadForThisFilter = widget.controller.isFirstLoadForFilter(filterKey);
        final isVipEffective = widget.controller.isVipEffective;
        
        // Loading inicial
        if (isLoading && notifications.isEmpty && isFirstLoadForThisFilter) {
          return const NotificationListSkeleton();
        }

        // Erro
        if (errorMessage != null && notifications.isEmpty) {
          return _ErrorState(
            errorMessage: errorMessage,
            i18n: i18n,
            onRetry: () => widget.controller.fetchNotifications(shouldRefresh: true),
          );
        }

        // Lista vazia
        if (notifications.isEmpty) {
          return GlimpseEmptyState(
            text: i18n.translate('no_notifications_yet'),
          );
        }

        // Lista com dados - 🚀 USANDO InfiniteListView
        return InfiniteListView(
          key: PageStorageKey('notif_${widget.filterIndex}'),
          controller: widget.controller.getScrollController(widget.filterIndex),
          itemCount: notifications.length,
          padding: EdgeInsets.only(top: 16.h),
          itemBuilder: (context, index) {
            final doc = notifications[index];
            
            return RepaintBoundary(
              child: NotificationItemWidget(
                key: ValueKey(doc.id),
                notification: doc,
                isVipEffective: isVipEffective,
                i18n: i18n,
                index: index,
                totalCount: notifications.length,
                onTap: () => widget.controller.markAsRead(doc.id),
                isLocallyRead: widget.controller.isNotificationRead(doc.id),
              ),
            );
          },
          onLoadMore: widget.controller.loadMore,
          isLoadingMore: widget.controller.isLoadingMore,
          exhausted: !hasMore,
        );
      },
    );
  }
}

/// Estado de erro
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.errorMessage,
    required this.i18n,
    required this.onRetry,
  });
  
  final String errorMessage;
  final AppLocalizations i18n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tryAgainText = i18n.translate('try_again');
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: onRetry,
            child: Text(tryAgainText),
          ),
        ],
      ),
    );
  }
}
