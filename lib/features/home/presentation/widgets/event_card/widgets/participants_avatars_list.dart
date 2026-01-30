import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/AnimatedSlideIn.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Widget reativo que exibe lista horizontal de avatares dos participantes
/// Usa dados pré-carregados do controller + Stream do Firestore para atualizações
class ParticipantsAvatarsList extends StatefulWidget {
  const ParticipantsAvatarsList({
    required this.eventId,
    required this.creatorId,
    this.preloadedParticipants,
    super.key,
  });

  final String eventId;
  final String? creatorId;
  /// Dados pré-carregados do EventCardController para exibição instantânea
  final List<Map<String, dynamic>>? preloadedParticipants;

  @override
  State<ParticipantsAvatarsList> createState() => _ParticipantsAvatarsListState();
}

class _ParticipantsAvatarsListState extends State<ParticipantsAvatarsList> {
  /// Cache local para exibir imediatamente (sem stream/firestore aqui)
  List<Map<String, dynamic>> _cachedParticipants = const [];

  /// 🎯 IDs dos participantes que devem ser animados
  final Set<String> _animateIds = <String>{};

  /// Flag para saber se é o primeiro build com dados (anima na primeira carga!)
  bool _isFirstLoadWithData = true;
  
  @override
  void initState() {
    super.initState();
    _updateParticipants(widget.preloadedParticipants ?? const []);
  }

  @override
  void didUpdateWidget(covariant ParticipantsAvatarsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preloadedParticipants != widget.preloadedParticipants) {
      _updateParticipants(widget.preloadedParticipants ?? const []);
    }
  }

  void _updateParticipants(List<Map<String, dynamic>> next) {
    final wasEmpty = _cachedParticipants.isEmpty;
    final oldIds = _cachedParticipants
        .map((p) => p['userId'] as String?)
        .whereType<String>()
        .toSet();
    final newIds = next
        .map((p) => p['userId'] as String?)
        .whereType<String>()
        .toSet();

    final addedIds = newIds.difference(oldIds);

    // ✅ PRIMEIRA CARGA COM DADOS: Animar TODOS (slide-in suave)
    if (_isFirstLoadWithData && wasEmpty && next.isNotEmpty) {
      _animateIds
        ..clear()
        ..addAll(newIds);
      _isFirstLoadWithData = false;
    } 
    // ✅ Novos participantes entrando depois: animar apenas eles
    else if (!_isFirstLoadWithData && addedIds.isNotEmpty) {
      _animateIds
        ..clear()
        ..addAll(addedIds);
    } else {
      _animateIds.clear();
    }

    // ✅ ORDEM ESTÁVEL: Manter o primeiro participante (criador) fixo,
    // ordenar os demais por `userId` para evitar "troca de lugares" visual
    final sortedList = List<Map<String, dynamic>>.from(next);
    if (sortedList.length > 1) {
      // Preservar o primeiro (criador), ordenar o resto por userId
      final first = sortedList.removeAt(0);
      sortedList.sort((a, b) {
        final aId = a['userId'] as String? ?? '';
        final bId = b['userId'] as String? ?? '';
        return aId.compareTo(bId);
      });
      sortedList.insert(0, first);
    }
    _cachedParticipants = sortedList;

    // ✅ PRELOAD: Carregar avatares antes da UI renderizar
    for (final p in _cachedParticipants) {
      final pUserId = p['userId'] as String?;
      final pPhotoUrl = p['photoUrl'] as String?;
      if (pUserId != null && pPhotoUrl != null && pPhotoUrl.isNotEmpty) {
        UserStore.instance.preloadAvatar(pUserId, pPhotoUrl);
      }
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Altura fixa para evitar popping durante carregamento
    // Avatar (40) + spacing (4) + nome (17) + padding top (12) = 73
    const fixedHeight = 73.0;

    final participants = _cachedParticipants;

    return SizedBox(
      height: fixedHeight,
      child: participants.isEmpty
          ? const SizedBox.shrink()
          : _buildParticipantsList(participants),
    );
  }
  
  Widget _buildParticipantsList(List<Map<String, dynamic>> participants) {
    final visible = participants;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < visible.length; i++)
                _buildParticipantWidget(visible[i], i),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 🎯 Constrói widget do participante: anima se estiver na lista de animação
  Widget _buildParticipantWidget(Map<String, dynamic> participant, int index) {
    final userId = participant['userId'] as String;
    final shouldAnimate = _animateIds.contains(userId);
    
    final child = Padding(
      padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
      child: _ParticipantItem(
        key: ValueKey('participant_$userId'),
        participant: participant,
        isCreator: participant['isCreator'] == true,
      ),
    );
    
    // ✅ Animar com slide-in suave (primeira carga ou novos participantes)
    if (shouldAnimate) {
      return AnimatedSlideIn(
        key: ValueKey('anim_$userId'),
        delay: Duration(milliseconds: index * 80), // 80ms entre cada avatar
        duration: const Duration(milliseconds: 400),
        offsetX: 40.0,
        child: child,
      );
    }
    
    // ✅ Participantes existentes: renderiza estável, sem animação
    return child;
  }
}

/// Item individual de participante (avatar + nome)
class _ParticipantItem extends StatelessWidget {
  const _ParticipantItem({
    required this.participant,
    required this.isCreator,
    super.key,
  });

  final Map<String, dynamic> participant;
  final bool isCreator;

  @override
  Widget build(BuildContext context) {
    final userId = participant['userId'] as String;
    final photoUrl = participant['photoUrl'] as String?;
    final fullName = participant['fullName'] as String? ?? 'Anônimo';

    return Column(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              StableAvatar(
                userId: userId,
                photoUrl: photoUrl,
                size: 40,
                borderRadius: BorderRadius.circular(999),
                enableNavigation: true,
              ),
              if (isCreator)
                Positioned(
                  bottom: -2,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: GlimpseColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 50,
          child: Text(
            fullName,
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.textSubTitle,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}


