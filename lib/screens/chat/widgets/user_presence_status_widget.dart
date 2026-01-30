import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/screens/chat/models/user_model.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// ✅ OTIMIZADO: Widget de presença agora usa get() com polling (60s)
/// Antes: stream realtime = ~1 read/segundo
/// Depois: get() a cada 60s = ~1 read/minuto (98% redução)
class UserPresenceStatusWidget extends StatefulWidget {

  const UserPresenceStatusWidget({
    required this.userId, 
    required this.chatService, 
    super.key,
    this.isEvent = false,
    this.eventId,
  });
  final String userId;
  final ChatService chatService;
  final bool isEvent;
  final String? eventId;

  @override
  State<UserPresenceStatusWidget> createState() => _UserPresenceStatusWidgetState();
}

class _UserPresenceStatusWidgetState extends State<UserPresenceStatusWidget> {
  UserModel? _user;
  Timer? _refreshTimer;
  bool _isLoading = true;
  
  // ✅ Intervalo de refresh para presença (60 segundos)
  static const Duration _refreshInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    if (!widget.isEvent) {
      _loadPresence();
      // Timer periódico para atualizar presença
      _refreshTimer = Timer.periodic(_refreshInterval, (_) => _loadPresence());
    }
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  /// ✅ Carrega presença com get() único (cache de 60s no ChatService)
  Future<void> _loadPresence() async {
    if (!mounted) return;
    
    final user = await widget.chatService.getUserOnce(widget.userId);
    
    if (!mounted) return;
    
    setState(() {
      _user = user;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    // Para eventos, retorna apenas o activityText da coleção events
    if (widget.isEvent && widget.eventId != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const SizedBox();
          }
          
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final activityText = data?['activityText'] ?? data?['activity_text'] ?? '';
          
          if (activityText.isEmpty) return const SizedBox();
          
          return Text(
            activityText,
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
            overflow: TextOverflow.ellipsis,
          );
        },
      );
    }
    
    // ✅ OTIMIZADO: Presença via get() com cache (não mais stream)
    if (_isLoading || _user == null) {
      return const SizedBox();
    }
    
    final user = _user!;

    // Check user presence status
    if (user.isOnline ?? false) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            i18n.translate('ONLINE'),
            style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: GlimpseColors.textSubTitle,
            ),
          ),
        ],
      );
    }
    
    // Verificar último login
    final lastLogin = user.lastLogin;
    if (lastLogin == null) {
      return Text(
        i18n.translate('offline'),
        style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: GlimpseColors.textSubTitle,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    // Usar TimeAgoHelper com i18n
    final timeAgoText = TimeAgoHelper.format(context, timestamp: lastLogin);

    // Exibir texto sem hífen
    return Text(
      "${i18n.translate('last_seen')} $timeAgoText",
      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: GlimpseColors.textSubTitle,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
