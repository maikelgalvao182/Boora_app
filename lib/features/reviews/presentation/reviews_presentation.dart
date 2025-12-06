/// Presentation Layer - Reviews Feature
/// 
/// Exports all components, dialogs, and screens for the reviews system
/// 
/// Usage:
/// ```dart
/// import 'package:partiu/features/reviews/presentation/reviews_presentation.dart';
/// 
/// // Para dialogs
/// await showReviewDialog(context, eventId, reviewedUserId);
/// 
/// // Para profile
/// ReviewStatsSection(stats: stats)
/// ReviewCardV2(review: review)
/// ```
library presentation;

// Components - Dialog Steps
export 'components/badge_selection_step.dart';
export 'components/comment_step.dart';
export 'components/rating_criteria_step.dart';

// Components - Profile Widgets
export 'components/review_card_v2.dart';
export 'components/review_stats_section.dart';

// Dialogs
export 'dialogs/review_dialog.dart';
export 'dialogs/review_dialog_controller.dart';

// Screens
export 'screens/pending_reviews_screen.dart';
