import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/push_types.dart';
import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/services/push_preferences_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';

/// Bottom sheet para configurações de notificações
class NotificationsSettingsDrawer extends StatefulWidget {
  const NotificationsSettingsDrawer({super.key});

  /// Abre o drawer de configurações de notificações
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationsSettingsDrawer(),
    );
  }

  @override
  State<NotificationsSettingsDrawer> createState() =>
      _NotificationsSettingsDrawerState();
}

class _NotificationsSettingsDrawerState
    extends State<NotificationsSettingsDrawer> {
  double _eventNotificationRadius = EVENT_NOTIFICATION_RADIUS_KM;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final settings = data?['advancedSettings'] as Map<String, dynamic>?;
        final savedRadius = settings?['eventNotificationRadiusKm'] as num?;

        if (savedRadius != null) {
          setState(() {
            _eventNotificationRadius = savedRadius.toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [NotificationsSettings] Erro ao carregar: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveEventNotificationRadius(double radius) async {
    final userId = AppState.currentUserId;
    if (userId == null || userId.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('Users').doc(userId).set({
        'advancedSettings': {
          'eventNotificationRadiusKm': radius,
          'eventNotificationRadiusUpdatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      debugPrint(
          '✅ [NotificationsSettings] Raio salvo: ${radius.toStringAsFixed(0)} km');
    } catch (e) {
      debugPrint('❌ [NotificationsSettings] Erro ao salvar raio: $e');
    }
  }

  Future<void> _updatePushPreference(PushType type, bool enabled) async {
    // 1. Update Firestore
    await PushPreferencesService.setEnabled(type, enabled);

    // 2. Update Local User (Optimistic)
    final user = SessionManager.instance.currentUser;
    if (user != null) {
      final newPrefs = Map<String, dynamic>.from(user.pushPreferences ?? {});
      newPrefs[PushPreferencesService.key(type)] = enabled;

      final newUser = user.copyWith(pushPreferences: newPrefs);
      await SessionManager.instance.saveUser(newUser);

      if (mounted) setState(() {}); // Rebuild UI
    }
  }

  String _tr(AppLocalizations i18n, String key, String fallback) {
    final value = i18n.translate(key);
    return value.isNotEmpty ? value : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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

                    // Header: Título + Close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Título alinhado à esquerda
                        Text(
                          _tr(i18n, 'notification_settings',
                              'Configurar Notificações'),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: GlimpseColors.primaryColorLight,
                          ),
                        ),

                        // Botão fechar
                        const GlimpseCloseButton(
                          size: 32,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Conteúdo
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CupertinoActivityIndicator(),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Seção: Tipos de notificação
                      _buildSectionHeader(
                        context,
                        _tr(i18n, 'notification_types', 'Tipos de notificação'),
                      ),
                      const SizedBox(height: 8),

                      // Card com switches
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        color: GlimpseColors.lightTextField,
                        child: Column(
                          children: [
                            _buildSwitchItem(
                              context,
                              icon: Iconsax.notification,
                              title: _tr(i18n, 'global_notifications',
                                  'Notificações gerais'),
                              subtitle: _tr(
                                  i18n,
                                  'global_notifications_desc',
                                  'Novos eventos, atualizações e mais'),
                              value: PushPreferencesService.isEnabled(
                                PushType.global,
                                SessionManager
                                    .instance.currentUser?.pushPreferences,
                              ),
                              onChanged: (v) =>
                                  _updatePushPreference(PushType.global, v),
                            ),
                            Divider(
                                height: 1,
                                indent: 56,
                                color: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.10)),
                            _buildSwitchItem(
                              context,
                              icon: Iconsax.message,
                              title: _tr(
                                  i18n, 'event_messages', 'Mensagens dos eventos'),
                              subtitle: _tr(i18n, 'event_messages_desc',
                                  'Chat dos eventos que você participa'),
                              value: PushPreferencesService.isEnabled(
                                PushType.chatEvent,
                                SessionManager
                                    .instance.currentUser?.pushPreferences,
                              ),
                              onChanged: (v) =>
                                  _updatePushPreference(PushType.chatEvent, v),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Seção: Raio de eventos
                      _buildSectionHeader(
                        context,
                        _tr(i18n, 'event_radius', 'Raio de eventos'),
                      ),
                      const SizedBox(height: 8),

                      // Card com slider
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        color: GlimpseColors.lightTextField,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: const Icon(
                                      Iconsax.location,
                                      size: 20,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _tr(
                                              i18n,
                                              'event_notification_radius',
                                              'Raio de notificações'),
                                          style: GoogleFonts.getFont(
                                            FONT_PLUS_JAKARTA_SANS,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _tr(
                                              i18n,
                                              'event_notification_radius_desc',
                                              'Receba notificações de eventos criados dentro deste raio'),
                                          style: GoogleFonts.getFont(
                                            FONT_PLUS_JAKARTA_SANS,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Valor atual
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: GlimpseColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_eventNotificationRadius.toStringAsFixed(0)} km (${(_eventNotificationRadius * 0.621371).toStringAsFixed(0)} mi)',
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: GlimpseColors.primary,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Slider
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: GlimpseColors.primary,
                                  inactiveTrackColor:
                                      GlimpseColors.primary.withValues(alpha: 0.2),
                                  thumbColor: GlimpseColors.primary,
                                  overlayColor:
                                      GlimpseColors.primary.withValues(alpha: 0.1),
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 10,
                                  ),
                                ),
                                child: Slider(
                                  value: _eventNotificationRadius,
                                  min: 1,
                                  max: 30,
                                  divisions: 29,
                                  onChanged: (value) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _eventNotificationRadius = value;
                                    });
                                  },
                                  onChangeEnd: (value) {
                                    _saveEventNotificationRadius(value);
                                  },
                                ),
                              ),

                              // Labels min/max
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '1 km',
                                      style: GoogleFonts.getFont(
                                        FONT_PLUS_JAKARTA_SANS,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black45,
                                      ),
                                    ),
                                    Text(
                                      '30 km',
                                      style: GoogleFonts.getFont(
                                        FONT_PLUS_JAKARTA_SANS,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Padding bottom para safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.40),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSwitchItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: value,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
            activeColor: GlimpseColors.primary,
          ),
        ],
      ),
    );
  }
}
