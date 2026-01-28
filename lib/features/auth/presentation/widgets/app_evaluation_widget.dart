import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/core/constants/text_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:in_app_review/in_app_review.dart';

/// Widget de avaliação do app (review)
/// Reutilizável para Bride e Vendor com diferentes depoimentos
/// Replica exatamente a UI da TelaAvaliacaoBride/Vendor
class AppEvaluationWidget extends StatefulWidget {
  const AppEvaluationWidget({
    required this.isBride,
    super.key,
    this.shouldAutoRequestReview = false,
  });

  final bool isBride;
  final bool shouldAutoRequestReview;

  @override
  State<AppEvaluationWidget> createState() => _AppEvaluationWidgetState();
}

class _AppEvaluationWidgetState extends State<AppEvaluationWidget> {
  late AppLocalizations _i18n;
  bool _hasRequestedReview = false;
  bool _hasShownAutoPrompt = false;

  final List<String> _avatarPaths = const [
    'assets/images/avatar/avatar3.jpg',
    'assets/images/avatar/image 3.jpg',
    'assets/images/avatar/avatar11.jpg',
    'assets/images/avatar/image 4.jpg',
    'assets/images/avatar/image 7.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _scheduleAutoPromptIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AppEvaluationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldAutoRequestReview && !oldWidget.shouldAutoRequestReview) {
      _scheduleAutoPromptIfNeeded();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _i18n = AppLocalizations.of(context);
  }

  void _scheduleAutoPromptIfNeeded() {
    if (!widget.shouldAutoRequestReview) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 250), _maybeShowReviewPrompt);
    });
  }

  Future<void> _maybeShowReviewPrompt() async {
    if (_hasShownAutoPrompt) return;
    _hasShownAutoPrompt = true;

    // Sem dialog Material: tenta abrir direto o prompt nativo (iOS/Android).
    await _requestReview();
  }

  Future<void> _requestReview() async {
    if (_hasRequestedReview) return;
    _hasRequestedReview = true;
    
    try {
      if (!mounted) return;
      final inAppReview = InAppReview.instance;
      
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await inAppReview.openStoreListing(appStoreId: '6755944656');
      }
    } catch (e) {
      AppLogger.error('Error requesting review: $e', tag: 'AppEvaluationWidget');
    }
  }

  List<_TestimonialData> _getTestimonials() {
    // isBride = false significa que é criador de atividades
    // isBride = true significa que é participante
    if (widget.isBride) {
      // Depoimentos de participantes
      return [
        _TestimonialData(
          name: _i18n.translate('testimonial_participant_1_name'),
          text: _i18n.translate('testimonial_participant_1_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_participant_2_name'),
          text: _i18n.translate('testimonial_participant_2_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_participant_3_name'),
          text: _i18n.translate('testimonial_participant_3_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_participant_4_name'),
          text: _i18n.translate('testimonial_participant_4_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_participant_5_name'),
          text: _i18n.translate('testimonial_participant_5_text'),
        ),
      ];
    } else {
      // Depoimentos de criadores de atividades
      return [
        _TestimonialData(
          name: _i18n.translate('testimonial_creator_1_name'),
          text: _i18n.translate('testimonial_creator_1_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_creator_2_name'),
          text: _i18n.translate('testimonial_creator_2_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_creator_3_name'),
          text: _i18n.translate('testimonial_creator_3_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_creator_4_name'),
          text: _i18n.translate('testimonial_creator_4_text'),
        ),
        _TestimonialData(
          name: _i18n.translate('testimonial_creator_5_name'),
          text: _i18n.translate('testimonial_creator_5_text'),
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const _RatingSummary(rating: 4.5, reviewsCount: 63),
        const SizedBox(height: 20),
        Center(
          child: Text(
            _i18n.translate('partiu_was_created_for_people_like_you'),
            textAlign: TextAlign.center,
            style: TextStyles.evaluationTitle,
          ),
        ),
        const SizedBox(height: 20),
        _AvatarStack(avatarPaths: _avatarPaths),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _i18n.translate('over_50k_people_discovering_new_activities'),
            textAlign: TextAlign.center,
            style: TextStyles.highlightDescription,
          ),
        ),
        const SizedBox(height: 24),
        // Lista de depoimentos (todos os 5)
        ..._getTestimonials().asMap().entries.map((entry) {
          final index = entry.key;
          final testimonial = entry.value;
          final avatar = _avatarPaths[index % _avatarPaths.length];
          return Padding(
            padding: EdgeInsets.only(bottom: index < _getTestimonials().length - 1 ? 12 : 0),
            child: _TestimonialCard(testimonial: testimonial, avatarPath: avatar),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Modelo de dados para depoimento
class _TestimonialData {
  const _TestimonialData({required this.name, required this.text});
  final String name;
  final String text;
}

/// Resumo da avaliação (EXATO da TelaAvaliacaoBride)
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.rating, required this.reviewsCount});
  final double rating;
  final int reviewsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const _Laurel(side: 'left'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      rating.toStringAsFixed(1),
                      style: TextStyles.ratingTitle,
                    ),
                    const SizedBox(width: 8),
                    for (int i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SvgPicture.string(_starSvg, width: 20, height: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context).translate('over_x_app_reviews').replaceAll('{count}', (reviewsCount / 1000).floor().toString()),
                  textAlign: TextAlign.center,
                  style: TextStyles.reviewsDescription,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _Laurel(side: 'right'),
        ],
      ),
    );
  }
}

/// Laurel (EXATO da TelaAvaliacaoBride)
class _Laurel extends StatelessWidget {
  const _Laurel({required this.side});
  final String side;

  @override
  Widget build(BuildContext context) {
    final path = 'assets/images/${side == 'right' ? 'direito.png' : 'esquerdo.png'}';
    return Image.asset(path, width: 72, height: 72, fit: BoxFit.contain);
  }
}

/// Stack de avatares (EXATO da TelaAvaliacaoBride)
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.avatarPaths});
  final List<String> avatarPaths;

  @override
  Widget build(BuildContext context) {
    const double size = 64;
    const double overlap = 18;
    final totalWidth = size + (avatarPaths.length - 1) * (size - overlap);
    return Center(
      child: SizedBox(
        width: totalWidth,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < avatarPaths.length; i++)
              Positioned(
                left: i * (size - overlap),
                child: _CircularAvatar(path: avatarPaths[i], size: size),
              ),
          ],
        ),
      ),
    );
  }
}

/// Avatar circular (EXATO da TelaAvaliacaoBride)
class _CircularAvatar extends StatelessWidget {
  const _CircularAvatar({required this.path, required this.size});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        color: Colors.grey.shade200,
      ),
      child: ClipOval(
        child: Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) {
            return Image.asset(
              'assets/images/avatar/bride.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Icon(Icons.person, size: size * 0.5, color: Colors.grey.shade500),
            );
          },
        ),
      ),
    );
  }
}

/// Card de depoimento (EXATO da TelaAvaliacaoBride)
class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({required this.testimonial, required this.avatarPath});
  final _TestimonialData testimonial;
  final String avatarPath;

  @override
  Widget build(BuildContext context) {
    // Parse name and category separated by bullet point
    final parts = testimonial.name.split(' • ');
    final name = parts.first;
    final category = parts.length > 1 ? parts[1] : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: ClipOval(
                  child: Image.asset(
                    avatarPath,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Image.asset(
                      'assets/images/avatar/image 2.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (c2, e2, s2) => const Icon(Icons.person, size: 20, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyles.testimonialName,
                    ),
                    if (category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        category,
                        style: TextStyles.testimonialCategory,
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: SvgPicture.string(_starSvg, width: 16, height: 16),
                    ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(
            testimonial.text,
            style: TextStyles.testimonialText,
          ),
        ],
      ),
    );
  }
}

/// SVG da estrela (EXATO da TelaAvaliacaoBride)
const String _starSvg = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M13.7299 3.51014L15.4899 7.03014C15.7299 7.52014 16.3699 7.99014 16.9099 8.08014L20.0999 8.61014C22.1399 8.95014 22.6199 10.4301 21.1499 11.8901L18.6699 14.3701C18.2499 14.7901 18.0199 15.6001 18.1499 16.1801L18.8599 19.2501C19.4199 21.6801 18.1299 22.6201 15.9799 21.3501L12.9899 19.5801C12.4499 19.2601 11.5599 19.2601 11.0099 19.5801L8.01991 21.3501C5.87991 22.6201 4.57991 21.6701 5.13991 19.2501L5.84991 16.1801C5.97991 15.6001 5.74991 14.7901 5.32991 14.3701L2.84991 11.8901C1.38991 10.4301 1.85991 8.95014 3.89991 8.61014L7.08991 8.08014C7.61991 7.99014 8.25991 7.52014 8.49991 7.03014L10.2599 3.51014C11.2199 1.60014 12.7799 1.60014 13.7299 3.51014Z" fill="#C47E3D"/></svg>';
