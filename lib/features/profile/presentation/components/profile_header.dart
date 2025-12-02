import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:circle_flags/circle_flags.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/constants/glimpse_variables.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';

/// Header principal do perfil com foto, nome, idade e informações básicas
/// 
/// Inclui:
/// - Foto de perfil com overlay de gradiente
/// - Nome, idade, profissão e localização
/// - Sistema reativo via UserStore
class ProfileHeader extends StatefulWidget {

  const ProfileHeader({
    required this.user,
    required this.isMyProfile,
    required this.i18n,
    super.key,
  });

  final User user;
  final bool isMyProfile;
  final AppLocalizations i18n;

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  late final ValueNotifier<String> _imageUrlNotifier;

  @override
  void initState() {
    super.initState();
    _imageUrlNotifier = ValueNotifier<String>(_getFirstValidImage());
    
    // Observa mudanças na foto via UserStore
    final avatarNotifier = UserStore.instance.getAvatarNotifier(widget.user.userId);
    avatarNotifier.addListener(_updateAvatar);
  }

  void _updateAvatar() {
    final avatarNotifier = UserStore.instance.getAvatarNotifier(widget.user.userId);
    final provider = avatarNotifier.value;
    
    if (provider is NetworkImage) {
      final url = provider.url;
      if (url.isNotEmpty && url != _imageUrlNotifier.value) {
        _imageUrlNotifier.value = url;
      }
    }
  }

  @override
  void dispose() {
    final avatarNotifier = UserStore.instance.getAvatarNotifier(widget.user.userId);
    avatarNotifier.removeListener(_updateAvatar);
    _imageUrlNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GlimpseStyles.horizontalMargin),
        child: AspectRatio(
          aspectRatio: 1 / 1.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Stack(
              children: [
                // Imagem de fundo
                _buildImage(),
                
                // Gradiente overlay
                _buildGradientOverlay(),
                
                // Informações do usuário
                _buildUserInfo(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return ValueListenableBuilder<String>(
      valueListenable: _imageUrlNotifier,
      builder: (context, imageUrl, _) {
        if (imageUrl.isEmpty) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[300],
            child: const Icon(
              Icons.person,
              size: 100,
              color: Colors.white,
            ),
          );
        }

        return Image.network(
          imageUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.grey[300],
              child: const Icon(
                Icons.person,
                size: 100,
                color: Colors.white,
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
            stops: const [0.5, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nome, Idade com Bandeira
          _buildNameWithAgeAndFlag(),
          
          const SizedBox(height: 8),
          
          // Localização (Cidade, Estado)
          _buildLocationWithState(),
          
          const SizedBox(height: 8),
          
          // Instagram
          _buildInstagram(),
        ],
      ),
    );
  }

  Widget _buildNameWithAgeAndFlag() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getFromNotifier(widget.user.userId),
      builder: (context, from, _) {
        // Obtém informações do país se disponível
        final countryInfo = (from != null && from.isNotEmpty) ? getCountryInfo(from) : null;
        
        return Row(
          children: [
            // Bandeira do país (se disponível)
            if (countryInfo != null) ...[
              CircleFlag(
                countryInfo.flagCode,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            
            // Nome com badge
            Flexible(
              child: ReactiveUserNameWithBadge(
                userId: widget.user.userId,
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                iconSize: 18,
                spacing: 8,
              ),
            ),
            
            // Vírgula + Idade
            ValueListenableBuilder<int?>(
              valueListenable: UserStore.instance.getAgeNotifier(widget.user.userId),
              builder: (context, age, _) {
                if (age == null) return const SizedBox.shrink();
                return Text(
                  ', $age',
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationWithState() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getCityNotifier(widget.user.userId),
      builder: (context, city, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: UserStore.instance.getStateNotifier(widget.user.userId),
          builder: (context, state, _) {
            final parts = <String>[];
            if (city != null && city.isNotEmpty) parts.add(city);
            if (state != null && state.isNotEmpty) parts.add(state);
            
            if (parts.isEmpty) return const SizedBox.shrink();
            
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Iconsax.location,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Text(
                  parts.join(', '),
                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInstagram() {
    return ValueListenableBuilder<String?>(
      valueListenable: UserStore.instance.getInstagramNotifier(widget.user.userId),
      builder: (context, instagram, _) {
        if (instagram == null || instagram.isEmpty) return const SizedBox.shrink();
        
        return GestureDetector(
          onTap: () => _openInstagram(instagram),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Iconsax.instagram,
                size: 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                instagram,
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.8),
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openInstagram(String username) async {
    // Remove @ se estiver presente
    final cleanUsername = username.replaceAll('@', '');
    final url = Uri.parse('https://www.instagram.com/$cleanUsername');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _getFirstValidImage() {
    // Prioriza userProfilePhoto
    if (widget.user.userProfilePhoto.isNotEmpty) {
      return widget.user.userProfilePhoto;
    }
    
    // Fallback: photoUrl
    if (widget.user.photoUrl != null && widget.user.photoUrl!.isNotEmpty) {
      return widget.user.photoUrl!;
    }
    
    // Fallback: galeria
    if (widget.user.userGallery != null && widget.user.userGallery!.isNotEmpty) {
      final firstImageUrl = widget.user.userGallery!['0'];
      if (firstImageUrl != null && firstImageUrl.toString().isNotEmpty) {
        return firstImageUrl.toString();
      }
    }
    
    return '';
  }
}
