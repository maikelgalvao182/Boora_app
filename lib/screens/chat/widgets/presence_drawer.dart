import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/models/user.dart' as app_user;
import 'package:partiu/core/utils/interests_helper.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/presentation/widgets/user_card.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/repositories/user_repository.dart';

/// Drawer para exibir lista de presenças confirmadas de um evento
class PresenceDrawer extends StatefulWidget {
  const PresenceDrawer({
    required this.eventId,
    super.key,
  });

  final String eventId;

  @override
  State<PresenceDrawer> createState() => _PresenceDrawerState();
}

class _PresenceDrawerState extends State<PresenceDrawer> {
  List<String> _myInterests = [];
  List<Map<String, dynamic>> _participants = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMyInterests();
    _loadParticipants();
  }

  /// Carrega interesses do usuário atual via Repository
  Future<void> _loadMyInterests() async {
    final repository = UserRepository();
    final myUserData = await repository.getCurrentUserData();
    
    if (myUserData != null) {
      _myInterests = List<String>.from(myUserData['interests'] ?? []);
    }
    
    if (mounted) {
      setState(() {});
      debugPrint('👤 Meus interesses carregados: ${_myInterests.length}');
    }
  }

  /// ✅ Carrega participantes uma vez (sem stream)
  Future<void> _loadParticipants() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('EventApplications')
          .where('eventId', isEqualTo: widget.eventId)
          .where('status', whereIn: ['approved', 'autoApproved'])
          .get();

      if (!mounted) return;

      setState(() {
        _participants = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'userId': data['userId'] as String,
            'presence': data['presence'] as String? ?? 'Talvez',
          };
        }).toList();
        _loading = false;
      });

      debugPrint('✅ ${_participants.length} participantes carregados');
    } catch (e) {
      debugPrint('❌ Erro ao carregar participantes: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Handle e header
          Padding(
            padding: const EdgeInsets.only(
              top: 12,
              left: 20,
              right: 20,
            ),
            child: Column(
              children: [
                // Handle
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
                const SizedBox(height: 16),

                // Título
                Text(
                  i18n.translate('presence_confirmed_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: GlimpseColors.primaryColorLight,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Lista de presenças
          Expanded(
            child: _buildParticipantsList(i18n),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildParticipantsList(AppLocalizations i18n) {
    // Loading
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlimpseEmptyState.standard(
              text: i18n.translate('presence_load_error'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadParticipants,
              child: Text(i18n.translate('try_again')),
            ),
          ],
        ),
      );
    }

    // Empty
    if (_participants.isEmpty) {
      return Center(
        child: GlimpseEmptyState.standard(
          text: i18n.translate('presence_none_confirmed'),
        ),
      );
    }

    // List
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _participants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        try {
          final participant = _participants[index];
          final userId = participant['userId'] as String;
          final presence = participant['presence'] as String;
          
          return _PresenceUserCard(
            userId: userId,
            presence: presence,
            myInterests: _myInterests,
            index: index,
          );
        } catch (e, stack) {
          debugPrint('❌ Erro ao renderizar item $index: $e');
          debugPrint('Stack: $stack');
          return const SizedBox.shrink();
        }
      },
    );
  }
}

/// Card de usuário com status de presença
class _PresenceUserCard extends StatefulWidget {
  const _PresenceUserCard({
    required this.userId,
    required this.presence,
    required this.myInterests,
    this.index,
  });

  final String userId;
  final String presence;
  final List<String> myInterests;
  final int? index;

  @override
  State<_PresenceUserCard> createState() => _PresenceUserCardState();
}

class _PresenceUserCardState extends State<_PresenceUserCard> {
  app_user.User? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserWithCommonInterests();
  }

  /// Carrega usuário e calcula interesses em comum usando Repository
  Future<void> _loadUserWithCommonInterests() async {
    final repository = UserRepository();
    
    // Buscar dados do usuário
    final userData = await repository.getUserById(widget.userId);
    
    if (userData != null) {
      // Calcular interesses em comum usando Helper
      final userInterests = List<String>.from(userData['interests'] ?? []);
      userData['commonInterests'] = InterestsHelper.getCommonInterestsList(
        userInterests,
        widget.myInterests,
      );
      
      if (mounted) {
        setState(() {
          _user = app_user.User.fromDocument(userData);
          _isLoading = false;
        });
      }
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _user == null) {
      return const SizedBox(
        height: 82,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return UserCard(
      userId: widget.userId,
      user: _user,
      trailingWidget: _PresenceBadge(presence: widget.presence),
      index: widget.index,
    );
  }
}

/// Badge de presença com estilo baseado no status
class _PresenceBadge extends StatelessWidget {
  const _PresenceBadge({
    required this.presence,
  });

  final String presence;

  String _localizedPresenceLabel(AppLocalizations i18n) {
    switch (presence) {
      case 'Vou':
        return i18n.translate('presence_yes');
      case 'Talvez':
        return i18n.translate('presence_maybe');
      case 'Não vou':
        return i18n.translate('presence_no');
      default:
        return presence;
    }
  }

  String _getEmoji() {
    switch (presence) {
      case 'Vou':
        return '✅';
      case 'Talvez':
        return '🤔';
      case 'Não vou':
        return '❌';
      default:
        return '🤔';
    }
  }

  Color _getBackgroundColor() {
    switch (presence) {
      case 'Vou':
        return GlimpseColors.primaryLight;
      case 'Talvez':
        return const Color(0xFFE3F2FD); // Azul clarinho
      case 'Não vou':
        return const Color(0xFFFFEBEE); // Vermelho clarinho
      default:
        return GlimpseColors.primaryLight;
    }
  }

  Color _getTextColor() {
    switch (presence) {
      case 'Vou':
        return GlimpseColors.primaryDarker; // Verde escuro
      case 'Talvez':
        return const Color(0xFF1976D2); // Azul
      case 'Não vou':
        return const Color(0xFFD32F2F); // Vermelho
      default:
        return GlimpseColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final label = _localizedPresenceLabel(i18n);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '${_getEmoji()} $label',
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _getTextColor(),
        ),
      ),
    );
  }
}
