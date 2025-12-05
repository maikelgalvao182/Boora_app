import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/controllers/profile_controller.dart';
import 'package:partiu/features/profile/presentation/components/profile_content_builder.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Tela de perfil otimizada seguindo arquitetura MVVM
/// 
/// Features:
/// - Usa ProfileController para gerenciar estado
/// - Integrado com UserStore para dados reativos
/// - Pull-to-refresh nativo
/// - Auto-registra visitas
/// - Carrega reviews dinamicamente
class ProfileScreenOptimized extends StatefulWidget {
  
  const ProfileScreenOptimized({
    required this.user, 
    required this.currentUserId, 
    super.key,
  });
  
  final User user;
  final String currentUserId;

  @override
  State<ProfileScreenOptimized> createState() => _ProfileScreenOptimizedState();
}

class _ProfileScreenOptimizedState extends State<ProfileScreenOptimized>
    with AutomaticKeepAliveClientMixin {
  late final ProfileController _controller;
  late AppLocalizations _i18n;
  bool _visitRecorded = false;

  @override
  void initState() {
    super.initState();
    
    debugPrint('🚀 [ProfileScreen] Inicializando para userId: ${widget.user.userId.substring(0, 8)}...');
    
    _controller = ProfileController(
      userId: widget.user.userId,
      initialUser: widget.user,
    );
    
    // Aguarda frame inicial para carregar dados
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        debugPrint('📥 [ProfileScreen] Carregando dados do perfil');
        _controller.load(widget.user.userId);
      } else {
        debugPrint('⚠️  [ProfileScreen] Widget não mais montado, cancelando carregamento');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _i18n = AppLocalizations.of(context);
    
    // Garante que temos dados iniciais
    if (widget.user.userFullname.isNotEmpty) {
      if (_controller.profile.value == null || 
          _controller.profile.value!.userFullname.isEmpty) {
        _controller.profile.value = widget.user;
      }
    }
    
    // Registra visita (uma vez)
    if (!_visitRecorded) {
      _visitRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _controller.registerVisit(widget.currentUserId);
          }
        });
      });
    }
  }

  Future<void> _handleRefresh() async {
    await _controller.refresh(widget.user.userId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final myProfile = _controller.isMyProfile(widget.currentUserId);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          myProfile ? _i18n.translate('my_profile') : _i18n.translate('profile'),
          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        leading: GlimpseBackButton.iconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onPressed: () => Navigator.of(context).pop(),
          color: Colors.black87,
        ),
        actions: myProfile ? [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: SizedBox(
              width: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Iconsax.edit_2, size: 22),
                color: Colors.black87,
                onPressed: () {
                  context.push(AppRoutes.editProfile);
                },
              ),
            ),
          ),
        ] : null,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isLoading,
        builder: (context, isLoading, child) {
          if (isLoading && _controller.profile.value == null) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return ValueListenableBuilder<String?>(
            valueListenable: _controller.error,
            builder: (context, errorMessage, child) {
              if (errorMessage != null && _controller.profile.value == null) {
                return _buildErrorState(errorMessage);
              }
              
              return _buildContent(myProfile);
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _i18n.translate('error_load_profile'),
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _controller.refresh(widget.user.userId),
            icon: const Icon(Icons.refresh),
            label: Text(_i18n.translate('retry')),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent(bool myProfile) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Pull-to-refresh
        CupertinoSliverRefreshControl(
          onRefresh: _handleRefresh,
          refreshTriggerPullDistance: 120,
          refreshIndicatorExtent: 80,
          builder: (context, mode, pulledExtent, triggerDistance, indicatorExtent) {
            final percentage = (pulledExtent / triggerDistance).clamp(0.0, 1.0);
            final isRefreshing = mode == RefreshIndicatorMode.refresh ||
                mode == RefreshIndicatorMode.armed;

            final spinnerOpacity = isRefreshing ? 1.0 : percentage;
            final spinnerOffset = (1 - percentage) * 20;

            return SizedBox(
              height: pulledExtent,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, spinnerOffset),
                  child: Opacity(
                    opacity: spinnerOpacity,
                    child: const CupertinoActivityIndicator(radius: 14),
                  ),
                ),
              ),
            );
          },
        ),
        
        // Conteúdo usando ProfileContentBuilder
        SliverToBoxAdapter(
          child: ValueListenableBuilder<User?>(
            valueListenable: _controller.profile,
            builder: (context, profile, _) {
              final displayUser = profile ?? widget.user;

              return ProfileContentBuilder(
                controller: _controller,
                displayUser: displayUser,
                myProfile: myProfile,
                i18n: _i18n,
                currentUserId: widget.currentUserId,
              ).build();
            },
          ),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    debugPrint('🗑️  [ProfileScreen] Dispose chamado para userId: ${widget.user.userId.substring(0, 8)}...');
    _controller.release();
    super.dispose();
  }
}
