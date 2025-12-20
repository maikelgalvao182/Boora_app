import 'package:partiu/features/conversations/utils/conversation_styles.dart';
// REMOVIDO: import 'package:partiu/widgets/platform_pull_to_refresh.dart'; - pull-to-refresh removido
import 'package:flutter/cupertino.dart';

class ConversationsList extends StatefulWidget {

  const ConversationsList({
    required this.itemCount,
    required this.buildTile,
    required this.isVipEffective,
    required this.controller,
    required this.onTap,
    super.key,
    // REMOVIDO: required this.onRefresh,
    this.onEndReached,
    this.isLoadingMore = false,
  });
  final int itemCount;
  final Widget Function(BuildContext context, int index) buildTile;
  final bool isVipEffective;
  final ScrollController controller;
  // REMOVIDO: onRefresh - pull-to-refresh foi removido
  final VoidCallback? onEndReached;
  final bool isLoadingMore;
  final VoidCallback onTap;

  @override
  State<ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<ConversationsList> {
  bool _hasTriggeredEndReached = false;

  @override
  void didUpdateWidget(ConversationsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset flag se a lista mudou (novos docs carregados ou alterados)
    if (oldWidget.itemCount != widget.itemCount) {
      _hasTriggeredEndReached = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: widget.itemCount + (widget.isLoadingMore ? 1 : 0),
      physics: const AlwaysScrollableScrollPhysics(),
      controller: widget.controller,
      padding: const EdgeInsets.only(top: 16),
      itemBuilder: (context, index) {
        // Footer loader
        if (widget.isLoadingMore && index == widget.itemCount) {
          return const Padding(
            padding: ConversationStyles.footerLoaderPadding,
            child: Center(
              child: SizedBox(
                width: ConversationStyles.loaderSize,
                height: ConversationStyles.loaderSize,
                child: _FooterLoader(),
              ),
            ),
          );
        }

        // Trigger loadMore when near end - com proteção contra múltiplas chamadas
        // Só dispara se ainda não foi disparado neste ciclo
        // [FIX] Adicionado verificação de tamanho mínimo para evitar disparos em listas pequenas (ex: 1 item)
        // Assumimos que se a lista é muito pequena (< 10), não precisamos de paginação ou já carregamos tudo.
        final isNearEnd = widget.itemCount >= 10 &&
                          index >= widget.itemCount - ConversationStyles.nearEndThreshold;
                          
        if (isNearEnd && widget.onEndReached != null && !_hasTriggeredEndReached && !widget.isLoadingMore) {
          _hasTriggeredEndReached = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.onEndReached != null) {
              widget.onEndReached!();
            }
          });
        }

        return widget.buildTile(context, index);
      },
    );
  }
}

class _FooterLoader extends StatelessWidget {
  const _FooterLoader();

  @override
  Widget build(BuildContext context) {
    return const CupertinoActivityIndicator(
      radius: ConversationStyles.footerLoaderRadius,
    );
  }
}
