import 'package:flutter/material.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/event_photo_feed/presentation/services/feed_onboarding_service.dart';

class EventPhotoFeedOnboarding extends StatefulWidget {
  const EventPhotoFeedOnboarding({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<EventPhotoFeedOnboarding> createState() => _EventPhotoFeedOnboardingState();
}

class _EventPhotoFeedOnboardingState extends State<EventPhotoFeedOnboarding> {
  final LiquidController _liquidController = LiquidController();
  int _currentPage = 0;
  bool _isCompleting = false;

  static const Color _screenColor1 = Colors.white;
  static const Color _screenColor2 = GlimpseColors.primary;
  static const Color _screenColor3 = Colors.white;

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;

    setState(() {
      _isCompleting = true;
    });

    try {
      await FeedOnboardingService.instance.markCompleted();
      if (!mounted) return;
      widget.onComplete();
    } finally {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages(context);
    final isLastPage = _currentPage == pages.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentPage > 0) {
          _liquidController.animateToPage(page: _currentPage - 1);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: (!_isCompleting && isLastPage) ? _completeOnboarding : null,
                child: LiquidSwipe(
                  pages: pages,
                  liquidController: _liquidController,
                  onPageChangeCallback: _onPageChanged,
                  waveType: WaveType.liquidReveal,
                  slideIconWidget: isLastPage
                      ? const SizedBox.shrink()
                      : Icon(
                          Icons.arrow_back_ios,
                          color: isLastPage ? Colors.transparent : _indicatorColor,
                          size: 20,
                        ),
                  positionSlideIcon: 0.54,
                  enableSideReveal: true,
                  enableLoop: false,
                  ignoreUserGestureWhileAnimating: true,
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  if (!isLastPage)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          pages.length,
                          (index) => _buildPageIndicator(index),
                        ),
                      ),
                    ),
                  if (isLastPage)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 0,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isCompleting ? null : _completeOnboarding,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _screenColor2,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isCompleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  AppLocalizations.of(context)
                                      .translate('feed_onboarding_button_got_it'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _indicatorColor {
    final isPrimaryScreen = _currentPage == 1;
    return isPrimaryScreen ? Colors.white : GlimpseColors.primary;
  }

  Widget _buildPageIndicator(int index) {
    final isPrimaryScreen = _currentPage == 1;
    final activeColor = isPrimaryScreen ? Colors.white : GlimpseColors.primary;
    final inactiveColor = isPrimaryScreen
        ? Colors.white.withValues(alpha: 0.4)
        : GlimpseColors.primary.withValues(alpha: 0.3);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: _currentPage == index ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? activeColor : inactiveColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  List<Widget> _buildPages(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return [
      _OnboardingPage(
        backgroundColor: _screenColor1,
        imageAssetPath: 'assets/images/onboarding2/on1.png',
        title: i18n.translate('feed_onboarding_title_1'),
        subtitle: '',
        subtitleSpans: [
          TextSpan(
            text: i18n.translate('feed_onboarding_body_1_part_1'),
          ),
        ],
        textColor: GlimpseColors.primaryColorLight,
        extraWidget: _InfoCard(
          text: '${i18n.translate('feed_onboarding_body_1_part_2')}${i18n.translate('feed_onboarding_body_1_part_2_rest')}',
          textColor: GlimpseColors.primaryColorLight,
          borderColor: GlimpseColors.primary.withValues(alpha: 0.25),
        ),
      ),
      _OnboardingPage(
        backgroundColor: _screenColor2,
        imageAssetPath: 'assets/images/onboarding2/on2.png',
        title: i18n.translate('feed_onboarding_title_2'),
        subtitle: '',
        textColor: Colors.white,
        extraWidget: Column(
          children: [
            _InfoCard(
              text: i18n.translate('feed_onboarding_card_2_rule_1'),
              textColor: GlimpseColors.primaryColorLight,
              borderColor: Colors.white,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              text: i18n.translate('feed_onboarding_card_2_rule_2'),
              textColor: GlimpseColors.primaryColorLight,
              borderColor: Colors.white,
              backgroundColor: Colors.white,
            ),
            if (i18n.translate('feed_onboarding_body_2_footer').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                i18n.translate('feed_onboarding_body_2_footer'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
      _OnboardingPage(
        backgroundColor: _screenColor3,
        imageAssetPath: 'assets/images/onboarding2/on3.png',
        title: i18n.translate('feed_onboarding_title_3'),
        subtitle: '',
        textColor: GlimpseColors.primaryColorLight,
        extraWidget: Column(
          children: [
            _InfoCard(
              text: i18n.translate('feed_onboarding_card_3_rule_1'),
              textColor: GlimpseColors.primaryColorLight,
              borderColor: GlimpseColors.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InfoCard(
                text: i18n.translate('feed_onboarding_card_3_rule_2_short'),
                textColor: GlimpseColors.primaryColorLight,
                borderColor: GlimpseColors.primary.withValues(alpha: 0.25),
              ),
            ),
            Text(
              i18n.translate('feed_onboarding_body_3_footer'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: GlimpseColors.primaryColorLight.withValues(alpha: 0.85),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ];
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.backgroundColor,
    this.icon,
    this.imageAssetPath,
    required this.title,
    required this.subtitle,
    this.subtitleSpans,
    required this.textColor,
    this.extraWidget,
  }) : assert(icon != null || imageAssetPath != null, 'Informe icon ou imageAssetPath');

  final Color backgroundColor;
  final IconData? icon;
  final String? imageAssetPath;
  final String title;
  final String subtitle;
  final List<InlineSpan>? subtitleSpans;
  final Color textColor;
  final Widget? extraWidget;

  @override
  Widget build(BuildContext context) {
    const double imageSize = 168;
    const double imageContainerPadding = 36;
    const double bottomContentPadding = 84;
    final isPrimaryBackground = backgroundColor == GlimpseColors.primary;
    final containerColor = isPrimaryBackground
      ? Colors.white.withValues(alpha: 0.2)
      : GlimpseColors.primary.withValues(alpha: 0.12);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: backgroundColor,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, bottomContentPadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 344),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(imageContainerPadding),
                  decoration: BoxDecoration(
                    color: containerColor,
                    shape: BoxShape.circle,
                  ),
                  child: imageAssetPath != null
                      ? Image.asset(
                          imageAssetPath!,
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.contain,
                          opacity: const AlwaysStoppedAnimation(0.92),
                          semanticLabel: title,
                        )
                      : Icon(
                          icon,
                          size: 80,
                          color: textColor,
                        ),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
                if (subtitleSpans != null || subtitle.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  subtitleSpans != null
                      ? RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 16,
                              color: textColor.withValues(alpha: 0.9),
                              height: 1.5,
                            ),
                            children: subtitleSpans,
                          ),
                        )
                      : Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: textColor.withValues(alpha: 0.9),
                            height: 1.5,
                          ),
                        ),
                ],
                if (extraWidget != null) ...[
                  const SizedBox(height: 16),
                  extraWidget!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.text,
    required this.textColor,
    required this.borderColor,
    this.backgroundColor,
  });

  final String text;
  final Color textColor;
  final Color borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor ?? borderColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1.4,
        ),
      ),
    );
  }
}
