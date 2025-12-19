import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/pull_to_refresh.dart';
import 'package:partiu/features/home/presentation/screens/advanced_filters_screen.dart';
import 'package:partiu/features/home/presentation/screens/find_people/find_people_controller.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';
import 'package:partiu/features/home/presentation/widgets/vip_locked_card.dart';
import 'package:partiu/features/subscription/services/vip_access_service.dart';
import 'package:partiu/features/home/domain/models/user_with_meta.dart';

/// Tela para encontrar pessoas na região
/// 
/// ✅ Usa ValueListenableBuilder para rebuild granular
/// ✅ Evita rebuilds desnecessários do StarBadge
class FindPeopleScreen extends StatefulWidget {
  const FindPeopleScreen({super.key});

  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  late final FindPeopleController _controller;
  late final ScrollController _scrollController;
  bool _vipDialogOpen = false;
  double _lastScrollPosition = 0.0;

  @override
  void initState() {
    super.initState();
    // Obtém instância singleton (não cria nova)
    _controller = FindPeopleController();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    final isVip = VipAccessService.isVip;
    debugPrint('🎯 [FindPeopleScreen] Usando controller singleton');
    debugPrint('👤 [FindPeopleScreen] Status VIP: ${isVip ? "✅ VIP ATIVO" : "❌ NÃO-VIP (bloqueio será aplicado)"}');
    
    // 🚀 Garante inicialização do controller (padrão lazy initialization)
    _controller.ensureInitialized();
  }

  @override
  void dispose() {
    // NÃO faz dispose do controller singleton
    // Ele deve persistir entre navegações para manter o estado
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final isVip = VipAccessService.isVip;
    
    if (isVip) {
      return;
    }

    final scrollPosition = _scrollController.position.pixels;
    final viewportHeight = _scrollController.position.viewportDimension;
    
    // 🔒 Detecta apenas quando está scrollando PARA BAIXO
    final isScrollingDown = scrollPosition > _lastScrollPosition;
    _lastScrollPosition = scrollPosition;
    
    if (!isScrollingDown) {
      return; // Ignorar scroll para cima
    }
    
    // Cada card tem ~80px de altura + 12px de separador = ~92px
    // Considerando padding de 20px no topo
    const cardHeight = 92.0;
    const topPadding = 20.0;
    
    // Calcular posição do 12º card (índice 11)
    // 11 cards anteriores * 92px + 20px padding = 1032px
    const card12Position = (11 * cardHeight) + topPadding;
    
    // O card 12 se torna visível quando: scrollPosition + viewportHeight >= posição do card
    final card12Visible = (scrollPosition + viewportHeight) >= card12Position;
    
    debugPrint('📜 [Scroll] Position: ${scrollPosition.toStringAsFixed(0)}px, Card12 visível: $card12Visible');
    
    // Se o card 12 está visível scrollando para baixo e não está VIP
    if (card12Visible && !_vipDialogOpen) {
      debugPrint('🔒 [Scroll] BLOQUEIO ATIVADO! Card 12 (VIP Lock) está visível');
      _vipDialogOpen = true;
      _showVipDialog();
    }
  }

  Future<void> _showVipDialog() async {
    debugPrint('🔒 [VipDialog] Abrindo dialog...');
    HapticFeedback.mediumImpact();
    await VipAccessService.checkOrShowDialog(context);
    debugPrint('🔒 [VipDialog] Dialog fechado');
    // Delay para evitar múltiplos triggers
    await Future.delayed(const Duration(seconds: 1));
    _vipDialogOpen = false;
    debugPrint('🔒 [VipDialog] Flag resetada');
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, i18n),
      body: _buildBody(i18n),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppLocalizations i18n) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: ValueListenableBuilder<List<User>>(
        valueListenable: _controller.users,
        builder: (context, usersList, _) {
          final count = usersList.length;
          final title = count > 0 
              ? '$count ${count == 1 ? 'pessoa' : 'pessoas'} na região'
              : 'Pessoas na região';
          
          return Text(
            title,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
            ),
          );
        },
      ),
          leading: GlimpseBackButton.iconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => Navigator.of(context).pop(),
            color: GlimpseColors.primaryColorLight,
          ),
          leadingWidth: 56,
          actions: [
            // Botão de filtros
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: SizedBox(
                width: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    IconsaxPlusLinear.setting_4,
                    size: 24,
                    color: GlimpseColors.textSubTitle,
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final result = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.85,
                        ),
                        child: const AdvancedFiltersScreen(),
                      ),
                    );
                    
                    // Se filtros foram aplicados, o LocationQueryService já emitiu
                    // novos dados no stream e o controller já foi atualizado
                    if (result == true) {
                      debugPrint('✅ Filtros aplicados, aguardando atualização automática do stream');
                    }
                  },
                ),
              ),
            ),
          ],
        );
  }

  Widget _buildBody(AppLocalizations i18n) {
    // Loading state
        return ValueListenableBuilder<bool>(
      valueListenable: _controller.isLoading,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: 5,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => const UserCardShimmer(),
          );
        }        // Error state
        return ValueListenableBuilder<String?>(
          valueListenable: _controller.error,
          builder: (context, errorMessage, _) {
            if (errorMessage != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      errorMessage,
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16,
                        color: GlimpseColors.textSubTitle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _controller.refresh,
                      child: Text(
                        'Tentar novamente',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: GlimpseColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Success/Empty state
            return ValueListenableBuilder<List<User>>(
              valueListenable: _controller.users,
              builder: (context, usersList, _) {
                // Empty state
                if (usersList.isEmpty) {
                  return Center(
                    child: GlimpseEmptyState.standard(
                      text: i18n.translate('no_people_found_nearby'),
                    ),
                  );
                }

                // Success state - Lista de usuários com Pull to Refresh
                return PlatformPullToRefresh(
                  onRefresh: _controller.refresh,
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  // 🔒 Limitar a 13 itens para não-VIP (12 cards + 1 VipLockedCard)
                  itemCount: VipAccessService.isVip 
                    ? usersList.length 
                    : (usersList.length > 12 ? 13 : usersList.length),
                  itemBuilder: (context, index) {
                    debugPrint('🎨 [ItemBuilder] Building index $index, isVip: ${VipAccessService.isVip}');
                    
                    // 🔒 Se não é VIP e chegou no 13º item (índice 12), mostra VipLockedCard
                    if (!VipAccessService.isVip && index == 12) {
                      debugPrint('🔒 [ItemBuilder] Renderizando VipLockedCard no índice 12');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: VipLockedCard(
                          onTap: () {
                            debugPrint('🔒 [VipLockedCard] Tap detectado!');
                            _showVipDialog();
                          },
                        ),
                      );
                    }
                    
                    final user = usersList[index];
                    
                    // Adiciona separador entre itens
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index < usersList.length - 1 ? 12 : 0,
                      ),
                      child: UserCard(
                        key: ValueKey(user.userId),
                        userId: user.userId,
                        user: user,
                        overallRating: user.overallRating,
                        index: index,
                        onTap: () {
                          // TODO: Navegar para perfil do usuário
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
