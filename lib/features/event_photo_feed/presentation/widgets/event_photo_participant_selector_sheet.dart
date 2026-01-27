import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/data/models/tagged_participant_model.dart';
import 'package:partiu/features/event_photo_feed/presentation/controllers/event_photo_composer_controller.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Provider para buscar participantes do evento com presence='Vou'
final eventParticipantsProvider = FutureProvider.family<List<_ParticipantInfo>, String>((ref, eventId) async {
  final firestore = FirebaseFirestore.instance;
  final i18n = await AppLocalizations.loadForLanguageCode(AppLocalizations.currentLocale);
  final fallbackUserName = i18n.translate('event_photo_user_fallback_name');
  
  // Buscar aplicações aprovadas com presence='Vou'
  final appsSnap = await firestore
      .collection('EventApplications')
      .where('eventId', isEqualTo: eventId)
      .where('status', whereIn: ['approved', 'autoApproved'])
      .where('presence', isEqualTo: 'Vou')
      .get();

  if (appsSnap.docs.isEmpty) {
    return [];
  }

  // Extrair userIds únicos
  final userIds = appsSnap.docs
      .map((d) => d.data()['userId'] as String?)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  if (userIds.isEmpty) {
    return [];
  }

  // Buscar dados dos usuários (chunked para evitar limite do whereIn)
  final participants = <_ParticipantInfo>[];
  const chunkSize = 10;

  for (var i = 0; i < userIds.length; i += chunkSize) {
    final chunk = userIds.sublist(i, (i + chunkSize).clamp(0, userIds.length));
    
    final usersSnap = await firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();

    for (final doc in usersSnap.docs) {
      final data = doc.data();
      participants.add(_ParticipantInfo(
        userId: doc.id,
        userName: (data['fullName'] as String?) ?? fallbackUserName,
        userPhotoUrl: data['photoUrl'] as String?,
      ));
    }
  }

  // Ordenar por nome
  participants.sort((a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));

  return participants;
});

class _ParticipantInfo {
  const _ParticipantInfo({
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
  });

  final String userId;
  final String userName;
  final String? userPhotoUrl;
}

/// Bottom sheet para selecionar participantes do evento
class EventPhotoParticipantSelectorSheet extends ConsumerStatefulWidget {
  const EventPhotoParticipantSelectorSheet({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  final String eventId;
  final String eventTitle;

  @override
  ConsumerState<EventPhotoParticipantSelectorSheet> createState() => _EventPhotoParticipantSelectorSheetState();
}

class _EventPhotoParticipantSelectorSheetState extends ConsumerState<EventPhotoParticipantSelectorSheet> {
  final Set<String> _selectedUserIds = {};

  @override
  void initState() {
    super.initState();
    // Pré-selecionar participantes já marcados no state
    final currentTagged = ref.read(eventPhotoComposerControllerProvider).taggedParticipants;
    _selectedUserIds.addAll(currentTagged.map((p) => p.userId));
  }

  void _toggleParticipant(_ParticipantInfo participant) {
    setState(() {
      if (_selectedUserIds.contains(participant.userId)) {
        _selectedUserIds.remove(participant.userId);
      } else {
        _selectedUserIds.add(participant.userId);
      }
    });
  }

  void _confirm(List<_ParticipantInfo> allParticipants) {
    final selected = allParticipants
        .where((p) => _selectedUserIds.contains(p.userId))
        .map((p) => TaggedParticipantModel(
              userId: p.userId,
              userName: p.userName,
              userPhotoUrl: p.userPhotoUrl,
            ))
        .toList();

    ref.read(eventPhotoComposerControllerProvider.notifier).setTaggedParticipants(selected);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final asyncParticipants = ref.watch(eventParticipantsProvider(widget.eventId));

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GlimpseColors.borderColorLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n.translate('event_photo_participants_title'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: GlimpseColors.primaryColorLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.eventTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.textSubTitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botão confirmar
                  asyncParticipants.whenOrNull(
                    data: (participants) => TextButton(
                      onPressed: () => _confirm(participants),
                      style: TextButton.styleFrom(
                        backgroundColor: _selectedUserIds.isEmpty
                            ? Colors.transparent
                            : GlimpseColors.primaryColorLight,
                        foregroundColor: _selectedUserIds.isEmpty
                            ? GlimpseColors.primary
                            : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: Text(
                        _selectedUserIds.isEmpty
                            ? i18n.translate('skip')
                            : i18n
                                .translate('event_photo_confirm_with_count')
                                .replaceAll('{count}', _selectedUserIds.length.toString()),
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ) ?? const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 16),
              // Lista de participantes
              asyncParticipants.when(
                data: (participants) {
                  if (participants.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Center(
                        child: Text(
                          i18n.translate('event_photo_no_participants'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.textSubTitle,
                          ),
                        ),
                      ),
                    );
                  }

                  return Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: participants.length,
                      itemBuilder: (_, i) {
                        final p = participants[i];
                        final isSelected = _selectedUserIds.contains(p.userId);

                        return _ParticipantTile(
                          participant: p,
                          isSelected: isSelected,
                          onTap: () => _toggleParticipant(p),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CupertinoActivityIndicator(radius: 14)),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: Text(
                      i18n.translate('error_loading_participants'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.isSelected,
    required this.onTap,
  });

  final _ParticipantInfo participant;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            StableAvatar(
              userId: participant.userId,
              photoUrl: participant.userPhotoUrl,
              size: 44,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                participant.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
              ),
            ),
            // Checkbox visual
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? GlimpseColors.primaryColorLight : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? GlimpseColors.primaryColorLight : GlimpseColors.borderColorLight,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
