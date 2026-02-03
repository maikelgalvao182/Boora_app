import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/controllers/profile_controller.dart';
import 'package:partiu/features/profile/presentation/controllers/follow_controller.dart';
import 'package:partiu/features/profile/presentation/components/profile_content_builder_v2.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/report_hint_wrapper.dart';
import 'package:partiu/shared/widgets/report_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/utils/app_logger.dart';

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
  
  // FollowController mantido no State para evitar recriação quando profile muda
  FollowController? _followController;
  
  // Contador de builds para debug
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 [ProfileScreenOptimized] initState() chamado - widget.hashCode: ${widget.hashCode}');
    
    AppLogger.info(
      'Inicializando para userId: ${widget.user.userId.length > 8 ? widget.user.userId.substring(0, 8) : widget.user.userId}...',
      tag: 'ProfileScreen',
    );
    
    _controller = ProfileController(
      userId: widget.user.userId,
      initialUser: widget.user,
    );
    
    // Cria FollowController apenas se não for o próprio perfil
    final currentUserId = widget.currentUserId;
    if (currentUserId != widget.user.userId) {
      _followController = FollowController(
        myUid: currentUserId,
        targetUid: widget.user.userId,
      );
    }
    
    // Aguarda frame inicial para carregar dados
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        AppLogger.info('Carregando dados do perfil', tag: 'ProfileScreen');
        _controller.load(
          widget.user.userId,
          useStream: false,
          includeReviews: false,
        );
      } else {
        AppLogger.warning(
          'Widget não mais montado, cancelando carregamento',
          tag: 'ProfileScreen',
        );
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
    await _controller.refresh(
      widget.user.userId,
      useStream: false,
      includeReviews: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _buildCount++;
    debugPrint('🏠 [ProfileScreenOptimized] build() #$_buildCount - hashCode: ${widget.hashCode}, followController: ${_followController?.hashCode}');
    final myProfile = _controller.isMyProfile(widget.currentUserId);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: myProfile 
        ? GlimpseAppBar(
            title: _i18n.translate('my_profile'),
            onBack: () => Navigator.of(context).pop(),
            onAction: () => context.push(AppRoutes.editProfile),
            actionText: _i18n.translate('edit'),
          )
        : GlimpseAppBar(
            title: _i18n.translate('profile'),
            onBack: () => Navigator.of(context).pop(),
            actionWidget: ReportHintTooltip(
              child: ReportWidget(
                userId: widget.user.userId,
                iconSize: 24,
                iconColor: Colors.black87,
                onBlockSuccess: () {
                  if (mounted) {
                    context.go(AppRoutes.home);
                  }
                },
              ),
            ),
          ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isLoading,
        builder: (context, isLoading, child) {
          // Verificar se usuário está bloqueado (exceto próprio perfil)
          if (!myProfile && BlockService().isBlockedCached(widget.currentUserId, widget.user.userId)) {
            return _buildBlockedState();
          }
          
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

  Widget _buildBlockedState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Iconsax.slash, size: 64, color: Colors.grey),
          const SizedBox(height: 24),
          Text(
            _i18n.translate('profile_unavailable') ?? 'Perfil não disponível',
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _i18n.translate('blocked_user_profile_message') ?? 
              'Você não pode visualizar este perfil',
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
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
            onPressed: () => _controller.refresh(
              widget.user.userId,
              useStream: false,
              includeReviews: false,
            ),
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
        
        // Conteúdo usando ProfileContentBuilderV2
        SliverToBoxAdapter(
          child: ValueListenableBuilder<User?>(
            valueListenable: _controller.profile,
            builder: (context, profile, _) {
              final pid = profile?.userId ?? "null";
              debugPrint('🏠 [ProfileScreenOptimized] ValueListenableBuilder<User?> rebuild - profile changed: ${pid.length > 8 ? pid.substring(0, 8) : pid}');
              final displayUser = profile ?? widget.user;

              return ProfileContentBuilderV2(
                controller: _controller,
                displayUser: displayUser,
                myProfile: myProfile,
                i18n: _i18n,
                currentUserId: widget.currentUserId,
                followController: _followController,
              );
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
    AppLogger.info(
      'Dispose chamado para userId: ${widget.user.userId.length > 8 ? widget.user.userId.substring(0, 8) : widget.user.userId}...',
      tag: 'ProfileScreen',
    );
    _followController?.dispose();
    _controller.release();
    super.dispose();
  }
}
