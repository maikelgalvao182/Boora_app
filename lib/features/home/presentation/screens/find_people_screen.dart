import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/features/home/presentation/screens/advanced_filters_screen.dart';
import 'package:partiu/features/home/presentation/screens/find_people/find_people_controller.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/features/home/presentation/widgets/user_card_shimmer.dart';
import 'package:partiu/features/home/domain/models/user_with_meta.dart';

/// Tela para encontrar pessoas na região
class FindPeopleScreen extends StatefulWidget {
  const FindPeopleScreen({super.key});

  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  late FindPeopleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FindPeopleController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context),
      body: _buildBody(i18n),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final count = _controller.userIds.length;
    final title = count > 0 
        ? '$count ${count == 1 ? 'pessoa' : 'pessoas'} na região'
        : 'Pessoas na região';
    
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: Text(
        title,
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: GlimpseColors.primaryColorLight,
        ),
      ),
      leading: GlimpseBackButton.iconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: () => Navigator.of(context).pop(),
        color: GlimpseColors.primaryColorLight,
      ),
      leadingWidth: 56,
      actions: [
        // Botão de refresh
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                IconsaxPlusLinear.refresh,
                size: 22,
                color: GlimpseColors.textSubTitle,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                _controller.refresh();
              },
            ),
          ),
        ),
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
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AdvancedFiltersScreen(),
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
    if (_controller.isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: 5,
        itemBuilder: (context, index) => const UserCardShimmer(),
      );
    }

    // Error state
    if (_controller.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _controller.error!,
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

    // Empty state
    if (_controller.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma pessoa encontrada',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 16,
            color: GlimpseColors.textSubTitle,
          ),
        ),
      );
    }

    // Success state - Lista de usuários
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _controller.users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = _controller.users[index];
        return UserCard(
          key: ValueKey(user.userId),
          userId: user.userId,
          user: user,
          onTap: () {
            // TODO: Navegar para perfil do usuário
          },
        );
      },
    );
  }
}
