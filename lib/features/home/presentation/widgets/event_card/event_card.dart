import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_handler.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/event_action_buttons.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/event_formatted_text.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/participants_avatars_list.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/participants_counter.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:partiu/shared/widgets/place_details_modal.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/report_event_button.dart';

/// Bottom sheet de evento que exibe informações do criador e localização
/// 
/// Widget burro que apenas compõe widgets const baseado nos dados do controller
class EventCard extends StatefulWidget {
  const EventCard({
    required this.controller,
    required this.onActionPressed,
    super.key,
  });

  final EventCardController controller;
  final VoidCallback onActionPressed;

  /// Exibe o EventCard como um bottom sheet
  static Future<void> show({
    required BuildContext context,
    required EventCardController controller,
    required VoidCallback onActionPressed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventCard(
        controller: controller,
        onActionPressed: onActionPressed,
      ),
    );
  }

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  late EventCardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Abre modal com informações do local
  void _showPlaceDetails() {
    PlaceDetailsModal.show(
      context,
      _controller.eventId,
      preloadedData: _controller.locationData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GlimpseColors.borderColorLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Header: Nome do criador centralizado + Report Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Nome centralizado (usando ReactiveUserNameWithBadge como no UserCard)
                  if (_controller.creatorId != null)
                    Center(
                      child: ReactiveUserNameWithBadge(
                        userId: _controller.creatorId!,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: GlimpseColors.primaryColorLight,
                        ),
                        iconSize: 16, // Badge maior para o header do EventCard
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Center(
                      child: Text(
                        _controller.creatorFullName ?? '',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: GlimpseColors.primaryColorLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Botão de denúncia à direita
                  Positioned(
                    right: 0,
                    child: ReportEventButton(eventId: _controller.eventId),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Conteúdo principal
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildContent(i18n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations i18n) {
    // Error state
    if (_controller.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            _controller.error!,
            style: DialogStyles.messageStyle.copyWith(
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Success state
    if (_controller.hasData) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Texto formatado com emoji (sem fullName, está no header)
          EventFormattedText(
            fullName: '',
            activityText: _controller.activityText ?? '',
            locationName: _controller.locationName ?? '',
            dateText: _controller.formattedDate,
            timeText: _controller.formattedTime,
            onLocationTap: _showPlaceDetails,
            emoji: _controller.emoji,
          ),
          
          const SizedBox(height: 24),
          
          // Contador de participantes (stream)
          ParticipantsCounter(
            controller: _controller,
            eventId: _controller.eventId,
            singularLabel: i18n.translate('participant_singular'),
            pluralLabel: i18n.translate('participant_plural'),
          ),
          
          // Lista de avatares (preload + stream)
          ParticipantsAvatarsList(
            eventId: _controller.eventId,
            creatorId: _controller.creatorId,
            preloadedParticipants: _controller.approvedParticipants,
          ),
          
          const SizedBox(height: 24),

          // Botões de ação
          EventActionButtons(
            isApproved: _controller.isApproved,
            isCreator: _controller.isCreator,
            isEnabled: _controller.isButtonEnabled,
            buttonText: i18n.translate(_controller.buttonText),
            chatButtonText: _controller.chatButtonText,
            leaveButtonText: _controller.leaveButtonText,
            deleteButtonText: _controller.deleteButtonText,
            isApplying: _controller.isApplying,
            isLeaving: _controller.isLeaving,
            isDeleting: _controller.isDeleting,
            onChatPressed: () => EventCardHandler.handleButtonPress(
              context: context,
              controller: _controller,
              onActionSuccess: widget.onActionPressed,
            ),
            onLeavePressed: () => EventCardHandler.handleLeaveEvent(
              context: context,
              controller: _controller,
            ),
            onDeletePressed: () => EventCardHandler.handleDeleteEvent(
              context: context,
              controller: _controller,
            ),
            onSingleButtonPressed: () => EventCardHandler.handleButtonPress(
              context: context,
              controller: _controller,
              onActionSuccess: widget.onActionPressed,
            ),
          ),
        ],
      );
    }

    // No data state
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          i18n.translate('no_data_available'),
          style: DialogStyles.messageStyle,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
