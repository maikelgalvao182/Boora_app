import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/AnimatedSlideIn.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Widget reativo que exibe lista horizontal de avatares dos participantes
/// Usa Stream direto do Firestore - atualiza automaticamente ao participar/sair
class ParticipantsAvatarsList extends StatefulWidget {
  const ParticipantsAvatarsList({
    required this.eventId,
    required this.creatorId,
    this.maxVisible = 5,
    super.key,
  });

  final String eventId;
  final String? creatorId;
  final int maxVisible;

  @override
  State<ParticipantsAvatarsList> createState() => _ParticipantsAvatarsListState();
}

class _ParticipantsAvatarsListState extends State<ParticipantsAvatarsList> {
  /// Flag para saber se já recebemos dados do servidor
  bool _hasReceivedServerData = false;
  
  /// Flag para animar apenas na primeira renderização
  bool _hasAnimated = false;
  
  /// Cache local para exibir enquanto aguarda dados do servidor
  List<Map<String, dynamic>>? _cachedParticipants;
  
  /// Stream de participantes aprovados com dados do usuário
  Stream<List<Map<String, dynamic>>> get _participantsStream {
    debugPrint('🔵 [ParticipantsAvatarsList] Stream INICIADO para eventId: ${widget.eventId}');
    
    return FirebaseFirestore.instance
        .collection('EventApplications')
        .where('eventId', isEqualTo: widget.eventId)
        .where('status', whereIn: ['approved', 'autoApproved'])
        .snapshots()
        .asyncMap((snapshot) async {
          debugPrint('📥 [ParticipantsAvatarsList] Snapshot recebido');
          debugPrint('   └─ isFromCache: ${snapshot.metadata.isFromCache}');
          debugPrint('   └─ hasPendingWrites: ${snapshot.metadata.hasPendingWrites}');
          debugPrint('   └─ docs.length: ${snapshot.docs.length}');
          
          // Se é do cache E já recebemos dados do servidor antes,
          // ignorar para evitar avatar fantasma ao sair do evento
          if (snapshot.metadata.isFromCache && _hasReceivedServerData) {
            debugPrint('⚠️ [ParticipantsAvatarsList] Ignorando CACHE (já temos dados do servidor)');
            return _cachedParticipants ?? <Map<String, dynamic>>[];
          }
          
          // Marca que recebemos dados do servidor
          if (!snapshot.metadata.isFromCache) {
            _hasReceivedServerData = true;
          }
          
          final participants = <Map<String, dynamic>>[];
          
          for (final doc in snapshot.docs) {
            final userId = doc.data()['userId'] as String?;
            debugPrint('👤 [ParticipantsAvatarsList] Processando doc: ${doc.id}');
            debugPrint('   └─ userId: $userId');
            if (userId == null) continue;
            
            // Buscar dados do usuário
            final userDoc = await FirebaseFirestore.instance
                .collection('Users')
                .doc(userId)
                .get();
            
            debugPrint('📄 [ParticipantsAvatarsList] UserDoc exists: ${userDoc.exists}');
            
            if (userDoc.exists) {
              final userData = userDoc.data()!;
              final fullName = userData['fullName'] ?? 'Anônimo';
              final photoUrl = userData['photoUrl'] ?? '';
              
              debugPrint('✅ [ParticipantsAvatarsList] Dados do usuário:');
              debugPrint('   └─ fullName: $fullName');
              debugPrint('   └─ photoUrl: $photoUrl');
              debugPrint('   └─ isCreator: ${userId == widget.creatorId}');
              
              participants.add({
                'userId': userId,
                'fullName': fullName,
                'photoUrl': photoUrl,
                'isCreator': userId == widget.creatorId,
              });
            }
          }
          
          // Ordenar: criador sempre primeiro
          participants.sort((a, b) {
            if (a['isCreator'] == true) return -1;
            if (b['isCreator'] == true) return 1;
            return 0;
          });
          
          debugPrint('📊 [ParticipantsAvatarsList] Total participantes: ${participants.length}');
          for (var p in participants) {
            debugPrint('   └─ ${p['fullName']} (${p['userId']}) - photoUrl: ${p['photoUrl']}');
          }
          
          // Atualiza cache local
          _cachedParticipants = participants;
          
          return participants;
        });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _participantsStream,
      builder: (context, snapshot) {
        // Usa dados do snapshot ou cache local para evitar flicker
        final participants = snapshot.data ?? _cachedParticipants ?? [];
        
        if (participants.isEmpty) {
          return const SizedBox.shrink();
        }

        final visible = participants.take(widget.maxVisible).toList();
        final remaining = participants.length - visible.length;
        
        // Anima apenas na primeira vez que exibe avatares
        final shouldAnimate = !_hasAnimated;
        if (shouldAnimate && participants.isNotEmpty) {
          _hasAnimated = true;
        }

        return Column(
          children: [
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < visible.length; i++)
                  if (shouldAnimate)
                    AnimatedSlideIn(
                      key: ValueKey('anim_${visible[i]['userId']}'),
                      delay: Duration(milliseconds: i * 100),
                      offsetX: 60.0,
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                        child: _ParticipantItem(
                          participant: visible[i],
                          isCreator: visible[i]['isCreator'] == true,
                        ),
                      ),
                    )
                  else
                    Padding(
                      key: ValueKey(visible[i]['userId']),
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: _ParticipantItem(
                        participant: visible[i],
                        isCreator: visible[i]['isCreator'] == true,
                      ),
                    ),
                
                if (remaining > 0)
                  if (shouldAnimate)
                    AnimatedSlideIn(
                      delay: Duration(milliseconds: visible.length * 100),
                      offsetX: 60.0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _RemainingCounter(count: remaining),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _RemainingCounter(count: remaining),
                    ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Item individual de participante (avatar + nome)
class _ParticipantItem extends StatelessWidget {
  const _ParticipantItem({
    required this.participant,
    required this.isCreator,
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

/// Contador de participantes restantes (+X)
class _RemainingCounter extends StatelessWidget {
  const _RemainingCounter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '+$count',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.textSubTitle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(width: 50, height: 17),
      ],
    );
  }
}
