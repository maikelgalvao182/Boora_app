import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/core/utils/date_helper.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/stable_avatar.dart';

/// Card que exibe uma avaliação individual no perfil
/// 
/// Features:
/// - Avatar do avaliador com fallback
/// - Nome e data da avaliação
/// - Rating com estrelas
/// - Comentário com expansão "Ver mais"
class CommentCard extends StatefulWidget {

  const CommentCard({
    required this.review, 
    super.key,
    this.onTap,
  });
  
  final ReviewModel review;
  final VoidCallback? onTap;

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  bool _showFullComment = false;

  @override
  Widget build(BuildContext context) {
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    final reviewDate = DateHelper.formatRelativeDate(
      widget.review.createdAt,
      context: context,
    );

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: GlimpseColors.lightTextField,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar + Nome + Job Title
              Row(
                children: [
                  // Avatar
                  StableAvatar(
                    userId: widget.review.reviewerId,
                    size: 40.w,
                  ),
                  SizedBox(width: 12.w),
                  // Nome e Job Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ReactiveUserNameWithBadge(
                          userId: widget.review.reviewerId,
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            fontSize: (isCompactScreen ? 14 : 15).sp,
                            fontWeight: FontWeight.w700,
                            color: GlimpseColors.primaryColorLight,
                          ),
                          iconSize: 14.sp,
                          spacing: 4.w,
                        ),
                        SizedBox(height: 4.h),
                        ValueListenableBuilder<String?>(
                          valueListenable: UserStore.instance.getCityNotifier(widget.review.reviewerId),
                          builder: (context, city, _) {
                            return ValueListenableBuilder<String?>(
                              valueListenable: UserStore.instance.getStateNotifier(widget.review.reviewerId),
                              builder: (context, state, _) {
                                final parts = <String>[];
                                if (city != null && city.isNotEmpty) parts.add(city);
                                if (state != null && state.isNotEmpty) parts.add(state);
                                
                                if (parts.isEmpty) return const SizedBox.shrink();
                                
                                return Text(
                                  parts.join(', '),
                                  style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                                    fontSize: (isCompactScreen ? 12 : 13).sp,
                                    fontWeight: FontWeight.w600,
                                    color: GlimpseColors.textSubTitle,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Rating e Data
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStars(widget.review.overallRating),
                      SizedBox(height: 4.h),
                      Text(
                        reviewDate,
                        style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                          fontSize: (isCompactScreen ? 11 : 12).sp,
                          fontWeight: FontWeight.w400,
                          color: GlimpseColors.textSubTitle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Comentário (se existir)
              if (widget.review.comment != null &&
                  widget.review.comment!.isNotEmpty) ...[
                SizedBox(height: 10.h),
                _buildComment(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(
            Iconsax.star1,
            color: Colors.amber,
            size: 18.sp,
          );
        } else if (index < rating) {
          return Icon(
            Iconsax.star1,
            color: Colors.amber,
            size: 18.sp,
          );
        } else {
          return Icon(
            Iconsax.star,
            color: Colors.grey.shade300,
            size: 18.sp,
          );
        }
      }),
    );
  }

  Widget _buildComment() {
    final isCompactScreen = MediaQuery.sizeOf(context).width <= 360;
    final comment = widget.review.comment!;
    final maxLines = _showFullComment ? null : 3;

    final commentText = Text(
      comment,
      style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        fontSize: (isCompactScreen ? 13 : 14).sp,
        fontWeight: FontWeight.w500,
        color: Colors.black,
        height: 1.5,
      ),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
      softWrap: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        commentText,
        // Botão "Ver mais" se o texto for longo
        if (comment.length > 100)
          GestureDetector(
            onTap: () {
              setState(() {
                _showFullComment = !_showFullComment;
              });
            },
            child: Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                _showFullComment ? 'Mostrar menos' : 'Ver mais',
                style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                  fontSize: (isCompactScreen ? 13 : 14).sp,
                  fontWeight: FontWeight.w600,
                  color: GlimpseColors.primaryColorLight,
                ),
                softWrap: true,
              ),
            ),
          ),
      ],
    );
  }
}
