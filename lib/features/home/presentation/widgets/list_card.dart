import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/list_emoji_avatar.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/features/home/presentation/widgets/list_card/list_card_controller.dart';
import 'package:partiu/features/home/presentation/widgets/list_card_shimmer.dart';

/// Card de atividade para lista
/// 
/// Busca dados de:
/// - events: emoji, activityText, schedule
/// - EventApplications: participantes aprovados + contador
class ListCard extends StatefulWidget {
  const ListCard({
    required this.controller,
    this.onTap,
    super.key,
  });

  final ListCardController controller;
  final VoidCallback? onTap;

  @override
  State<ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<ListCard> {
  late ListCardController _controller;

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

  /// Constrói a pilha de avatares simplificada e unificada
  Widget _buildParticipantsStack() {
    final participants = _controller.recentParticipants;
    final totalCount = _controller.totalParticipantsCount;
    
    // Configurações unificadas de tamanho e estilo
    final double size = 40.w;
    final double border = 2.w;
    final double offset = 28.w; // Distância visual entre os itens
    
    final displayCount = participants.length > 4 ? 4 : participants.length;
    final hasCounter = totalCount > 0;
    
    // Lista de itens para empilhar (sem emoji - agora fica no texto)
    final List<Widget> items = [];
    
    // 1. Participantes
    for (int i = 0; i < displayCount; i++) {
      items.add(
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: border),
          ),
          child: StableAvatar(
            userId: participants[i]['userId'] as String,
            photoUrl: participants[i]['photoUrl'] as String?,
            size: size,
            borderRadius: BorderRadius.circular(999.r),
            enableNavigation: true,
          ),
        ),
      );
    }
    
    // 2. Contador (apenas número, sem +)
    if (hasCounter) {
      items.add(
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GlimpseColors.primaryLight,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: border),
          ),
          child: Text(
            totalCount.toString(),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: GlimpseColors.primary,
            ),
          ),
        ),
      );
    }

    // Se não tem itens, retorna vazio
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: size,
      width: size + (items.length - 1) * offset,
      child: Stack(
        children: [
          for (int i = 0; i < items.length; i++)
            Positioned(
              left: i * offset,
              child: items[i],
            ),
        ],
      ),
    );
  }

  /// Constrói o avatar de emoji do evento
  Widget _buildEmojiAvatar() {
    final emoji = _controller.emoji ?? ListEmojiAvatar.defaultEmoji;
    final double size = 56.w;
    
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: GlimpseColors.primaryLight,
      ),
      child: ClipOval(
        child: ListEmojiAvatar(
          emoji: emoji,
          eventId: _controller.eventId,
          size: size,
          emojiSize: 28.sp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Loading state
    if (_controller.isLoading) {
      return const ListCardShimmer();
    }

    // Error state
    if (_controller.error != null) {
      // No drawer (e outras listas), evento pode ficar inválido entre o snapshot e o fetch.
      // Nesses casos, não renderiza um card de erro para não poluir a lista.
      if (_controller.error == 'Atividade indisponível') {
        return const SizedBox.shrink();
      }

      return Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
            width: 1.w,
          ),
        ),
        child: Text(
          _controller.error!,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 13.sp,
            color: Colors.red,
          ),
        ),
      );
    }

    // Success state - Dados formatados
    final activityText = _controller.activityText ?? 'Atividade';
    final locationName = _controller.locationName;
    
    final scheduleDate = _controller.scheduleDate;
    String dateText = '';
    String timeText = '';
    if (scheduleDate != null) {
      dateText = 'dia ${DateFormat('dd/MM', 'pt_BR').format(scheduleDate)}';
      if (scheduleDate.hour != 0 || scheduleDate.minute != 0) {
        timeText = DateFormat('HH:mm').format(scheduleDate);
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('🔵 [ListCard] Tap no card - eventId: ${_controller.eventId}');
        debugPrint('🔵 [ListCard] activityText: $activityText');
        if (widget.onTap != null) {
          debugPrint('🔵 [ListCard] Chamando onTap callback');
          widget.onTap!();
        } else {
          debugPrint('⚠️ [ListCard] onTap é null!');
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
            width: 1.w,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row: Emoji à esquerda + Texto formatado à direita
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar de emoji
                _buildEmojiAvatar(),
                SizedBox(width: 12.w),
                // Texto formatado: "João quer jogar futebol em Parque dia 15/12 às 18:00"
                Expanded(
                  child: _buildFormattedText(
                    i18n: i18n,
                    creatorId: _controller.creatorId,
                    activityText: activityText,
                    locationName: locationName,
                    dateText: dateText,
                    timeText: timeText,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 16.h),
            
            // Base: Avatars (Esquerda)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildParticipantsStack(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói o texto formatado no estilo do EventCard
  /// Exemplo: "João quer jogar futebol em Parque Ibirapuera dia 15/12 às 18:00"
  Widget _buildFormattedText({
    required AppLocalizations i18n,
    required String? creatorId,
    required String activityText,
    required String? locationName,
    required String dateText,
    required String timeText,
  }) {
    final baseStyle = GoogleFonts.getFont(
      FONT_PLUS_JAKARTA_SANS,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
    );

    // Se tiver creatorId, usa ValueListenableBuilder para nome reativo
    if (creatorId != null && creatorId.isNotEmpty) {
      return ValueListenableBuilder<String?>(
        valueListenable: UserStore.instance.getNameNotifier(creatorId),
        builder: (context, creatorName, _) {
          final displayName = (creatorName ?? '').trim();
          return _buildRichText(
            baseStyle: baseStyle,
            i18n: i18n,
            creatorName: displayName,
            activityText: activityText,
            locationName: locationName,
            dateText: dateText,
            timeText: timeText,
          );
        },
      );
    }

    // Sem creatorId, mostra sem nome
    return _buildRichText(
      baseStyle: baseStyle,
      i18n: i18n,
      creatorName: '',
      activityText: activityText,
      locationName: locationName,
      dateText: dateText,
      timeText: timeText,
    );
  }

  Widget _buildRichText({
    required TextStyle baseStyle,
    required AppLocalizations i18n,
    required String creatorName,
    required String activityText,
    required String? locationName,
    required String dateText,
    required String timeText,
  }) {
    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle.copyWith(color: GlimpseColors.textSubTitle),
        children: [
          // Nome do criador (só se não vazio)
          if (creatorName.isNotEmpty) ...[
            TextSpan(
              text: creatorName,
              style: baseStyle.copyWith(color: GlimpseColors.primary),
            ),
            // Conectivo
            TextSpan(text: ' ${i18n.translate('event_formatted_wants')} '),
          ],
          
          // "quer" quando creatorName está vazio
          if (creatorName.isEmpty) ...[
            TextSpan(text: '${i18n.translate('event_formatted_wants').substring(0, 1).toUpperCase()}${i18n.translate('event_formatted_wants').substring(1)} '),
          ],
          
          // Atividade
          TextSpan(
            text: activityText,
            style: baseStyle.copyWith(color: GlimpseColors.primaryColorLight),
          ),
          
          // Local
          if (locationName != null && locationName.isNotEmpty) ...[
            TextSpan(text: ' ${i18n.translate('event_formatted_in')} '),
            TextSpan(
              text: locationName,
              style: baseStyle.copyWith(color: GlimpseColors.primary),
            ),
          ],
          
          // Data
          if (dateText.isNotEmpty) ...[
            TextSpan(text: ' $dateText'),
          ],
          
          // Horário
          if (timeText.isNotEmpty) ...[
            TextSpan(text: ' ${i18n.translate('event_formatted_at')} '),
            TextSpan(text: timeText),
          ],
        ],
      ),
    );
  }
}
