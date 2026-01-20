import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_handler.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/event_action_buttons.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/event_formatted_text.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/participants_avatars_list.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/participants_counter.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:partiu/shared/widgets/emoji_container.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/place_details_modal.dart';
import 'package:partiu/shared/widgets/report_event_button.dart';

/// Card de evento que exibe informações do criador e localização
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
    
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: const BoxConstraints(
          maxWidth: 500,
          minWidth: 300,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(24),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 56),

                // Error state
                if (_controller.error != null)
                  Padding(
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
                  )

                // Success state
                else if (_controller.hasData) ...[
                  // Texto formatado
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: EventFormattedText(
                      fullName: _controller.creatorFullName ?? '',
                      activityText: _controller.activityText ?? '',
                      locationName: _controller.locationName ?? '',
                      dateText: _controller.formattedDate,
                      timeText: _controller.formattedTime,
                      onLocationTap: _showPlaceDetails,
                    ),
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
                ] else
                  // No data state
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        i18n.translate('no_data_available'),
                        style: DialogStyles.messageStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            
            // Emoji no topo
            Positioned(
              top: -40,
              left: 0,
              right: 0,
              child: Center(
                child: _controller.emoji != null
                    ? EmojiContainer(
                        emoji: _controller.emoji!,
                        size: 80,
                        emojiSize: 40,
                        borderWidth: 6,
                        borderColor: Colors.white,
                      )
                    : const SizedBox(width: 80, height: 80),
              ),
            ),
            
            // Botões de ação no topo direito
            Positioned(
              top: 0,
              right: 0,
              child: Row(
                children: [
                  ReportEventButton(eventId: _controller.eventId),
                  const SizedBox(width: 8),
                  GlimpseCloseButton(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
