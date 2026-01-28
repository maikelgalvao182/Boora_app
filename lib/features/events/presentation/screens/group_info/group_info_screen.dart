import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/events/presentation/screens/group_info/group_info_controller.dart';
import 'package:partiu/features/events/presentation/screens/group_info/widgets/event_header_widget.dart';
import 'package:partiu/features/events/presentation/screens/group_info/widgets/map_and_error_widgets.dart';
import 'package:partiu/features/events/presentation/screens/group_info/widgets/settings_widgets.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/swipeable_member_card.dart';

/// Tela de informações do grupo/evento
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    required this.eventId,
    super.key,
  });

  final String eventId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late GroupInfoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GroupInfoController(eventId: widget.eventId);
    _controller.addListener(_onControllerChanged);
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // _controller.dispose(); // REMOVIDO: Controller é singleton/multiton e deve persistir
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Constrói o label para o botão de filtros/participantes
  String? _buildParticipantsLabel(AppLocalizations i18n) {
    final parts = <String>[];
    
    // Idade
    final minAge = _controller.eventMinAge;
    final maxAge = _controller.eventMaxAge;
    if (minAge != null && maxAge != null) {
      parts.add('$minAge-$maxAge');
    }
    
    // Gênero
    final gender = _controller.eventGender;
    if (gender != null && gender.isNotEmpty && gender != 'all') {
      final genderKey = 'gender_$gender';
      parts.add(i18n.translate(genderKey));
    }
    
    if (parts.isEmpty) {
      return i18n.translate('filters');
    }
    
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GlimpseAppBar(
        title: i18n.translate('group_info'),
      ),
      body: _controller.isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _buildBody(i18n),
    );
  }

  Widget _buildBody(AppLocalizations i18n) {
    if (_controller.error != null) {
      return ErrorStateWidget(
        errorMessage: _controller.error!,
        onRetry: _controller.refresh,
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(0),
            child: Column(
              children: [
                const SizedBox(height: 32),
                EventHeaderWidget(
                  eventId: widget.eventId,
                  emoji: _controller.eventEmoji,
                  eventName: _controller.eventName,
                  formattedDate: _controller.formattedEventDate,
                  participantCount: _controller.participantCount,
                  isCreator: _controller.isCreator,
                  onEditName: () => _controller.showEditNameDialog(context),
                  onEditDate: () => _controller.showEditScheduleDialog(context),
                  onEditCategory: _controller.isCreator
                      ? () => _controller.showEditCategoryDialog(context)
                      : null,
                  onEditParticipants: _controller.isCreator
                      ? () => _controller.showEditParticipantsDialog(context)
                      : null,
                  onEditLocation: _controller.isCreator
                      ? () => _controller.showEditLocationDialog(context)
                      : null,
                  categoryLabel: _controller.eventCategory != null
                      ? i18n.translate('category_${_controller.eventCategory}')
                      : null,
                  participantsLabel: _buildParticipantsLabel(i18n),
                  locationLabel: _controller.eventLocation,
                ),
                const SizedBox(height: 32),
                _buildSettings(i18n),
                const SizedBox(height: 24),
                if (_controller.eventLocation != null)
                  EventMapWidget(
                    locationText: _controller.eventLocation!,
                    onOpenMaps: _controller.openInMaps,
                  ),
                const SizedBox(height: 24),
                _buildMembersList(i18n),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          color: Colors.white,
          child: SafeArea(
            child: !_controller.isCreator 
                ? _buildLeaveButton(i18n) 
                : _buildDeleteButton(i18n),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(AppLocalizations i18n) {
    return Column(
      children: [
        SettingTileWidget(
          icon: IconsaxPlusBold.notification,
          iconColor: GlimpseColors.primary,
          title: i18n.translate('mute_notifications'),
          trailing: CupertinoSwitch(
            value: _controller.isMuted,
            onChanged: _controller.toggleMute,
            activeColor: GlimpseColors.primary,
          ),
        ),
        // Switch de privacidade apenas para o criador
        if (_controller.isCreator)
          PrivacySwitchWidget(
            isPrivate: _controller.isPrivate,
            isCreator: _controller.isCreator,
            onToggle: _controller.togglePrivacy,
          ),
      ],
    );
  }

  Widget _buildMembersList(AppLocalizations i18n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ValueListenableBuilder<List<String>>(
        valueListenable: _controller.participantsNotifier,
        builder: (context, participantUserIds, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${i18n.translate('members')} (${participantUserIds.length})',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.textSubTitle,
                ),
              ),
              const SizedBox(height: 12),
              if (participantUserIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    i18n.translate('no_members_yet'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      color: GlimpseColors.textSubTitle,
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: participantUserIds.length,
                  separatorBuilder: (context, index) => const SizedBox.shrink(),
                  itemBuilder: (context, index) {
                    final userId = participantUserIds[index];
                    
                    // Se for o owner, adiciona swipe-to-delete (exceto para si mesmo)
                    if (_controller.isCreator) {
                      final isCurrentUser = userId == _controller.creatorId;
                      
                      // Owner não tem swipe no próprio card
                      if (isCurrentUser) {
                        return Padding(
                          padding: EdgeInsets.zero,
                          child: UserCard(
                            key: ValueKey(userId),
                            userId: userId,
                            index: index,
                          ),
                        );
                      }
                      
                      // Outros membros têm swipe-to-delete
                      return Padding(
                        padding: EdgeInsets.zero,
                        child: SwipeableMemberCard(
                          key: ValueKey(userId),
                          userId: userId,
                          index: index,
                          deleteLabel: i18n.translate('remove'),
                          onDelete: () {
                            // Exibe dialog de confirmação e remove o participante
                            _controller.showRemoveParticipantDialog(
                              context,
                              userId,
                              'Participante', // TODO: Buscar nome real do usuário
                            );
                          },
                        ),
                      );
                    }
                    
                    // Para membros normais, apenas exibe o card
                    return Padding(
                      padding: EdgeInsets.zero,
                      child: UserCard(
                        key: ValueKey(userId),
                        userId: userId,
                        index: index,
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeleteButton(AppLocalizations i18n) {
    return GlimpseButton(
      text: i18n.translate('delete_activity'),
      backgroundColor: GlimpseColors.primary,
      textColor: Colors.white,
      onTap: () async {
        final confirmed = await GlimpseCupertinoDialog.showDestructive(
          context: context,
          title: i18n.translate('delete_event'),
          message: i18n.translate('delete_event_confirmation')
              .replaceAll('{event}', _controller.eventName),
          destructiveText: i18n.translate('delete'),
          cancelText: i18n.translate('cancel'),
        );

        if (confirmed == true && mounted) {
          // Controller agora cuida da navegação após deleção bem-sucedida
          await _controller.deleteEvent(context);
        }
      },
      height: 55,
    );
  }

  Widget _buildLeaveButton(AppLocalizations i18n) {
    return GlimpseButton(
      text: i18n.translate('leave_event'),
      backgroundColor: GlimpseColors.primary,
      textColor: Colors.white,
      onTap: () => _controller.showLeaveEventDialog(context),
      height: 55,
    );
  }
}
