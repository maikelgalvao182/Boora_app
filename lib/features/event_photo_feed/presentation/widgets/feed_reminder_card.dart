import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/presentation/screens/event_photo_composer_screen.dart';
import 'package:partiu/features/event_photo_feed/presentation/services/feed_reminder_service.dart';

/// Card flutuante que incentiva o usuário a postar fotos de eventos no feed.
///
/// Exibe imagem à esquerda e texto à direita com duas variações:
/// - Mensagem A (pré-evento): "Registre seu evento"
/// - Mensagem B (pós-evento): "Compartilhe fotos do seu evento"
///
/// Botões:
/// - Primário: "Abrir feed" → navega para criação de post
/// - Secundário: "Não mostrar mais" → dismiss definitivo
class FeedReminderCard extends StatefulWidget {
  const FeedReminderCard({
    super.key,
    required this.reminderType,
    required this.onDismiss,
  });

  final FeedReminderType reminderType;
  final VoidCallback onDismiss;

  @override
  State<FeedReminderCard> createState() => _FeedReminderCardState();
}

class _FeedReminderCardState extends State<FeedReminderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _animateOut(VoidCallback onComplete) async {
    await _animController.reverse();
    onComplete();
  }

  void _handleOpenFeed() {
    _animateOut(() {
      widget.onDismiss();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EventPhotoComposerScreen()),
      );
    });
  }

  void _handleDontShowAgain() {
    FeedReminderService.instance.dismissPermanently();
    _animateOut(widget.onDismiss);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final isPreEvent = widget.reminderType == FeedReminderType.preEvent;

    final title = isPreEvent
        ? i18n.translate('feed_reminder_pre_title')
        : i18n.translate('feed_reminder_post_title');

    final subtitle = isPreEvent
        ? i18n.translate('feed_reminder_pre_subtitle')
        : i18n.translate('feed_reminder_post_subtitle');

    final imagePath = isPreEvent
        ? 'assets/images/card1.png'
        : 'assets/images/card2.png';

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
              Center(
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 16.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 16.r,
                        offset: Offset(0, 4.h),
                      ),
                    ],
                    border: Border.all(
                      color: GlimpseColors.borderColorLight,
                      width: 1.w,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.r),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Imagem à esquerda
                          SizedBox(
                            width: 100.w,
                            child: Image.asset(
                              imagePath,
                              fit: BoxFit.cover,
                            ),
                          ),

                          // Textos e botões à direita
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(12.r),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Título
                                  Text(
                                    title,
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w700,
                                      color: GlimpseColors.primaryColorLight,
                                    ),
                                  ),

                                  SizedBox(height: 4.h),

                                  // Subtítulo
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.getFont(
                                      FONT_PLUS_JAKARTA_SANS,
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w400,
                                      color: GlimpseColors.textSubTitle,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  SizedBox(height: 12.h),

                                  // Botões
                                  Row(
                                    children: [
                                      // Botão primário: Abrir feed
                                      Expanded(
                                        child: SizedBox(
                                          height: 34.h,
                                          child: ElevatedButton(
                                            onPressed: _handleOpenFeed,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: GlimpseColors.primary,
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              padding: EdgeInsets.symmetric(horizontal: 12.w),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8.r),
                                              ),
                                            ),
                                            child: Text(
                                              i18n.translate('feed_reminder_open_feed'),
                                              style: GoogleFonts.getFont(
                                                FONT_PLUS_JAKARTA_SANS,
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      SizedBox(width: 8.w),

                                      // Botão secundário: Não mostrar mais
                                      SizedBox(
                                        height: 34.h,
                                        child: TextButton(
                                          onPressed: _handleDontShowAgain,
                                          style: TextButton.styleFrom(
                                            foregroundColor: GlimpseColors.textSubTitle,
                                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8.r),
                                            ),
                                          ),
                                          child: Text(
                                            i18n.translate('dont_show'),
                                            style: GoogleFonts.getFont(
                                              FONT_PLUS_JAKARTA_SANS,
                                              fontSize: 11.sp,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
