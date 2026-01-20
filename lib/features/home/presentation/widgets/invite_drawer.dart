import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/services/referral_service.dart';
import 'package:partiu/services/appsflyer_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Bottom sheet para convidar amigos e ganhar premium
class InviteDrawer extends StatefulWidget {
  const InviteDrawer({super.key});

  @override
  State<InviteDrawer> createState() => _InviteDrawerState();
}

class _InviteDrawerState extends State<InviteDrawer> {
  bool _isLinkCopied = false;
  bool _isGeneratingLink = false;
  String? _generatedLink;
  
  List<InvitedUser> _invitedUsers = [];
  int _referralInstallCount = 0;
  bool _isLoadingReferrals = true;

  @override
  void initState() {
    super.initState();
    _loadInviteLink();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // Buscar dados do usuário atual
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final installCount = data?['referralInstallCount'] ?? 0;
        
        setState(() {
          _referralInstallCount = installCount is int ? installCount : int.tryParse(installCount.toString()) ?? 0;
        });
      }

      // Buscar lista de usuários que usaram nosso referral
      final referralInstalls = await FirebaseFirestore.instance
          .collection('ReferralInstalls')
          .where('referrerId', isEqualTo: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .get();

      final invitedUsers = <InvitedUser>[];
      for (final doc in referralInstalls.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;
        
        if (userId != null) {
          // Buscar dados do usuário convidado
          final invitedUserDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(userId)
              .get();

          if (invitedUserDoc.exists) {
            final userData = invitedUserDoc.data();
            invitedUsers.add(InvitedUser(
              userId: userId,
              name: userData?['fullName'] ?? 'Usuário',
              photoUrl: userData?['photoUrl'],
              hasCreatedAccount: true, // Se está em ReferralInstalls, criou conta
              invitedAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _invitedUsers = invitedUsers;
          _isLoadingReferrals = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar dados de referral: $e');
      if (mounted) {
        setState(() {
          _isLoadingReferrals = false;
        });
      }
    }
  }

  Future<void> _loadInviteLink() async {
    setState(() {
      _isGeneratingLink = true;
    });

    // Tenta gerar via API do AppsFlyer primeiro
    final link = await ReferralService.instance.generateInviteLinkForCurrentUserAsync();
    
    if (mounted) {
      setState(() {
        _generatedLink = link;
        _isGeneratingLink = false;
      });
    }
  }

  void _copyInviteLink() {
    final link = _generatedLink;
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('error_generating_link'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    Clipboard.setData(ClipboardData(text: link));
    setState(() {
      _isLinkCopied = true;
    });
    
    // Log evento af_invite conforme documentação AppsFlyer
    _logInviteEvent();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).translate('link_copied'),
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: GlimpseColors.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLinkCopied = false;
        });
      }
    });
  }

  /// Loga evento af_invite no AppsFlyer quando o link é copiado
  void _logInviteEvent() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    AppsflyerService.instance.logInvite(
      channel: 'clipboard_copy',
      referrerId: currentUser.uid,
      campaign: 'user_invite',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final i18n = AppLocalizations.of(context);
    
    // Usar _referralInstallCount do Firestore em vez de calcular localmente
    final acceptedInvites = _referralInstallCount;
    final pendingInvites = 0; // Por enquanto não temos pending invites
    
    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Header com handle e botão de fechar
          Padding(
            padding: const EdgeInsets.only(
              top: 12,
              left: 20,
              right: 20,
              bottom: 16,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 32),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GlimpseColors.borderColorLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const GlimpseCloseButton(size: 32),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícone de presente
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: GlimpseColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '🎁',
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Título
                  Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: GlimpseColors.primaryColorLight,
                        ),
                        children: [
                          const TextSpan(text: 'Ganhe 90 dias de\n'),
                          TextSpan(
                            text: 'Premium grátis',
                            style: GoogleFonts.getFont(
                              FONT_PLUS_JAKARTA_SANS,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: GlimpseColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Subtítulo
                  Center(
                    child: Text(
                      'Use seu link e convide 10 amigos para usar o Boora e ganhe 3 meses grátis de assinatura Premium',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: GlimpseColors.textSubTitle,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Progresso
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GlimpseColors.primaryLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          icon: '✅',
                          value: '$acceptedInvites/10',
                          label: i18n.translate('accepted_invites'),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: GlimpseColors.borderColorLight,
                        ),
                        _buildStatItem(
                          icon: '⏳',
                          value: pendingInvites.toString(),
                          label: i18n.translate('pending_invites'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Campo de link para copiar
                  Text(
                    i18n.translate('your_invite_link'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GlimpseColors.primaryColorLight,
                    ),
                  ),

                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: _copyInviteLink,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _isLinkCopied 
                            ? GlimpseColors.primaryLight.withValues(alpha: 0.2)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isLinkCopied 
                              ? GlimpseColors.primary
                              : GlimpseColors.borderColorLight,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _isGeneratingLink
                                ? Row(
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: GlimpseColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        i18n.translate('generating_link'),
                                        style: GoogleFonts.getFont(
                                          FONT_PLUS_JAKARTA_SANS,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: GlimpseColors.textSubTitle,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    _generatedLink ?? i18n.translate('generating_link'),
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: GlimpseColors.primaryColorLight,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            _isLinkCopied ? Icons.check : Icons.copy,
                            size: 20,
                            color: _isLinkCopied 
                                ? GlimpseColors.primary
                                : GlimpseColors.textSubTitle,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Lista de convidados
                  if (_isLoadingReferrals) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ] else if (_invitedUsers.isNotEmpty) ...[
                    Text(
                      i18n.translate('invited_friends'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._invitedUsers.map((user) => _buildInvitedUserItem(user)),
                  ] else ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          'Nenhum convite enviado ainda.\nComece a convidar seus amigos!',
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: GlimpseColors.textSubTitle,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Text(
          icon,
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: GlimpseColors.textSubTitle,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInvitedUserItem(InvitedUser user) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: GlimpseColors.borderColorLight,
          ),
        ),
        child: Row(
          children: [
            StableAvatar(
              userId: user.userId,
              photoUrl: user.photoUrl,
              size: 48,
              enableNavigation: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GlimpseColors.primaryColorLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.hasCreatedAccount
                        ? AppLocalizations.of(context).translate('account_created')
                        : AppLocalizations.of(context).translate('invite_pending'),
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: user.hasCreatedAccount
                          ? GlimpseColors.primary
                          : GlimpseColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: user.hasCreatedAccount
                    ? GlimpseColors.primaryLight.withValues(alpha: 0.2)
                    : GlimpseColors.lightTextField,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                user.hasCreatedAccount ? '✓' : '⏳',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modelo de usuário convidado
class InvitedUser {
  final String userId;
  final String name;
  final String? photoUrl;
  final bool hasCreatedAccount;
  final DateTime invitedAt;

  const InvitedUser({
    required this.userId,
    required this.name,
    this.photoUrl,
    required this.hasCreatedAccount,
    required this.invitedAt,
  });
}
