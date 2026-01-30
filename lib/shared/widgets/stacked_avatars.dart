import 'package:flutter/material.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Widget compartilhável que mostra avatares empilhados de participantes
/// 
/// Busca automaticamente participantes aprovados via EventApplicationRepository (Singleton)
/// e usa GlobalCacheService para evitar queries desnecessárias ao Firestore.
/// 
/// **Recursos:**
/// - ✅ Busca automática de participantes aprovados
/// - ✅ Cache com TTL de 3 minutos (zero rebuilds desnecessários)
/// - ✅ Singleton repository (mesma instância reutilizada)
/// - ✅ Avatares empilhados com borda branca
/// - ✅ Texto com contador de membros
/// - ✅ Skeleton durante carregamento
/// - ✅ Suporta até 3 avatares visíveis
/// 
/// **Uso:**
/// ```dart
/// StackedAvatars(
///   eventId: eventId,
///   avatarSize: 22,
///   maxVisible: 3,
/// )
/// ```
class StackedAvatars extends StatefulWidget {
  const StackedAvatars({
    required this.eventId,
    this.avatarSize = 22.0,
    this.maxVisible = 3,
    this.showMemberCount = true,
    this.textStyle,
    super.key,
  });

  final String eventId;
  final double avatarSize;
  final int maxVisible;
  final bool showMemberCount;
  final TextStyle? textStyle;

  @override
  State<StackedAvatars> createState() => _StackedAvatarsState();
}

class _StackedAvatarsState extends State<StackedAvatars> {
  // 🔄 SINGLETON: Mesma instância reutilizada em todo o app
  final EventApplicationRepository _applicationRepo = EventApplicationRepository();
  final UserRepository _userRepo = UserRepository();
  
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    try {
      // 🚀 O repository já usa cache interno com TTL de 3 minutos
      // Se o cache existir, retorna imediatamente sem query ao Firestore
      final participants = await _applicationRepo.getApprovedApplicationsWithUserData(
        widget.eventId,
      );
      
      if (mounted) {
        setState(() {
          _participants = participants;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar participantes: $e');
      if (mounted) {
        setState(() {
          _error = 'error_loading_participants';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    // Loading state
    if (_isLoading) {
      return _buildSkeleton();
    }

    // Error state
    if (_error != null) {
      return const SizedBox.shrink();
    }

    // No participants
    if (_participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleParticipants = _participants.take(widget.maxVisible).toList();
    final totalCount = _participants.length;
    final membersTemplate = totalCount == 1
      ? i18n.translate('members_count_singular')
      : i18n.translate('members_count_plural');
    final membersText = membersTemplate.replaceAll('{count}', totalCount.toString());
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _buildStackedAvatars(visibleParticipants),
        if (widget.showMemberCount) ...[
          const SizedBox(width: 8),
          Text(
            membersText,
            style: widget.textStyle ?? GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStackedAvatars(List<Map<String, dynamic>> participants) {
    const double overlap = 14.0;
    final stackWidth = widget.avatarSize + ((participants.length - 1) * overlap);

    return SizedBox(
      width: stackWidth,
      height: widget.avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < participants.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                ),
                child: StableAvatar(
                  userId: participants[i]['userId'] as String,
                  photoUrl: participants[i]['photoUrl'] as String?,
                  size: widget.avatarSize,
                  enableNavigation: false,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    const double overlap = 14.0;
    final stackWidth = widget.avatarSize + ((widget.maxVisible - 1) * overlap);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          width: stackWidth,
          height: widget.avatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < widget.maxVisible; i++)
                Positioned(
                  left: i * overlap,
                  child: Container(
                    width: widget.avatarSize,
                    height: widget.avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GlimpseColors.lightTextField,
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.showMemberCount) ...[
          const SizedBox(width: 8),
          Container(
            width: 60,
            height: 12,
            decoration: BoxDecoration(
              color: GlimpseColors.lightTextField,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }
}
