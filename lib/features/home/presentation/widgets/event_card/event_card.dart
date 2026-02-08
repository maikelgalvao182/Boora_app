import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/card_color_helper.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/event_card_handler.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/event_action_buttons.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/event_formatted_text.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/participants_avatars_list.dart';
import 'package:partiu/features/home/presentation/widgets/event_card/widgets/participants_counter.dart';
import 'package:partiu/shared/widgets/dialogs/dialog_styles.dart';
import 'package:partiu/shared/widgets/list_emoji_avatar.dart';
import 'package:partiu/shared/widgets/place_details_modal.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/report_event_button.dart';
import 'package:partiu/shared/widgets/report_hint_wrapper.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

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
  /// Aguarda os participantes carregarem para evitar "pop" na UI
  static Future<void> show({
    required BuildContext context,
    required EventCardController controller,
    required VoidCallback onActionPressed,
  }) async {
    await controller.ensureEventDataLoaded();
    // 🎯 Aguardar participantes carregarem ANTES de abrir o modal
    // Isso evita o "pop" onde avatares aparecem depois do card abrir
    await controller.ensureParticipantsLoaded();
    
    if (!context.mounted) return;
    
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.r),
          topRight: Radius.circular(20.r),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: EdgeInsets.only(top: 12.h, left: 20.w, right: 20.w),
              child: Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: GlimpseColors.borderColorLight,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
            ),

            SizedBox(height: 12.h),

            // Header: Nome do criador centralizado + Report Button
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Conteúdo centralizado (Stack de Avatars + Nome)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Stack de Emoji + Avatar
                        SizedBox(
                          height: 64.h, // Reduzido de 80 para 64
                          width: 105.w, // Largura ajustada para o overlap
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 1. Emoji do evento (Esquerda)
                              Positioned(
                                left: 0,
                                child: Container(
                                  width: 64.w,
                                  height: 64.h,
                                  decoration: BoxDecoration(
                                    color: CardColorHelper.getColor(_controller.eventId.hashCode),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3.w,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: ListEmojiAvatar(
                                      emoji: _controller.emoji ?? ListEmojiAvatar.defaultEmoji,
                                      eventId: _controller.eventId,
                                      size: 64.w,
                                      emojiSize: 32.sp,
                                    ),
                                  ),
                                ),
                              ),

                              // 2. Avatar do criador (Direita)
                              if (_controller.creatorId != null)
                                Positioned(
                                  right: 0,
                                  child: Container(
                                    width: 64.w,
                                    height: 64.h,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3.w,
                                      ),
                                    ),
                                    child: StableAvatar(
                                      userId: _controller.creatorId!,
                                      size: 64.w,
                                      borderRadius: BorderRadius.circular(999.r),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Nome centralizado (usando ReactiveUserNameWithBadge como no UserCard)
                        if (_controller.creatorId != null)
                          ReactiveUserNameWithBadge(
                            userId: _controller.creatorId!,
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: GlimpseColors.primaryColorLight,
                            ),
                            iconSize: 14.w, // Badge ajustado proporcionalmente
                            textAlign: TextAlign.center,
                          )
                        else
                          Text(
                            _controller.creatorFullName ?? '',
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: GlimpseColors.primaryColorLight,
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),

                    // Botão de denúncia à direita (topo alinhado com o centro do header)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: ReportHintTooltip(
                        duration: const Duration(seconds: 3),
                        child: ReportEventButton(eventId: _controller.eventId),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Conteúdo principal
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
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
        padding: EdgeInsets.symmetric(vertical: 20.h),
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
