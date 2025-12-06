import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/features/reviews/data/models/pending_review_model.dart';
import 'package:partiu/features/reviews/data/repositories/review_repository.dart';
import 'package:partiu/features/reviews/presentation/dialogs/review_dialog.dart';
import 'package:intl/intl.dart';

/// Tela para exibir e gerenciar pending reviews
class PendingReviewsScreen extends StatefulWidget {
  const PendingReviewsScreen({super.key});

  @override
  State<PendingReviewsScreen> createState() => _PendingReviewsScreenState();
}

class _PendingReviewsScreenState extends State<PendingReviewsScreen> {
  final ReviewRepository _repository = ReviewRepository();
  List<PendingReviewModel>? _pendingReviews;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPendingReviews();
  }

  Future<void> _loadPendingReviews() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final reviews = await _repository.getPendingReviews();
      setState(() {
        _pendingReviews = reviews;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao carregar avaliações pendentes';
        _isLoading = false;
      });
    }
  }

  Future<void> _openReviewDialog(PendingReviewModel pending) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReviewDialog(
        eventId: pending.eventId,
        revieweeId: pending.revieweeId,
        revieweeName: pending.revieweeName,
        revieweePhotoUrl: pending.revieweePhotoUrl,
        reviewerRole: pending.reviewerRole,
        pendingReviewId: pending.pendingReviewId,
      ),
    );

    // Se review foi enviado, recarrega lista
    if (result == true) {
      _loadPendingReviews();
    }
  }

  Future<void> _dismissReview(PendingReviewModel pending) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Descartar avaliação?',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Tem certeza que não quer avaliar ${pending.revieweeName}?',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Descartar',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontWeight: FontWeight.w600,
                color: GlimpseColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _repository.dismissPendingReview(pending.pendingReviewId);
        _loadPendingReviews();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Avaliação descartada',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: GlimpseColors.textSecondary,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao descartar avaliação',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: GlimpseColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Avaliações Pendentes',
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: GlimpseColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GlimpseColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: GlimpseColors.error.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 16,
                color: GlimpseColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPendingReviews,
              style: ElevatedButton.styleFrom(
                backgroundColor: GlimpseColors.primary,
              ),
              child: Text(
                'Tentar novamente',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_pendingReviews == null || _pendingReviews!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: GlimpseColors.success,
            ),
            const SizedBox(height: 24),
            Text(
              'Tudo em dia!',
              style: GoogleFonts.getFont(
                FONT_PLUS_JAKARTA_SANS,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: GlimpseColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Você não tem avaliações pendentes no momento',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  color: GlimpseColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingReviews,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingReviews!.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final pending = _pendingReviews![index];
          return _PendingReviewCard(
            pending: pending,
            onTapEvaluate: () => _openReviewDialog(pending),
            onTapDismiss: () => _dismissReview(pending),
          );
        },
      ),
    );
  }
}

class _PendingReviewCard extends StatelessWidget {
  final PendingReviewModel pending;
  final VoidCallback onTapEvaluate;
  final VoidCallback onTapDismiss;

  const _PendingReviewCard({
    required this.pending,
    required this.onTapEvaluate,
    required this.onTapDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final daysRemaining = pending.daysRemaining;
    final isUrgent = daysRemaining <= 2;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUrgent
              ? GlimpseColors.error.withOpacity(0.3)
              : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com evento
            Row(
              children: [
                Text(
                  pending.eventEmoji,
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending.eventTitle,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: GlimpseColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (pending.eventLocation != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: GlimpseColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pending.eventLocation!,
                                style: GoogleFonts.getFont(
                                  FONT_PLUS_JAKARTA_SANS,
                                  fontSize: 13,
                                  color: GlimpseColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Info da pessoa
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: GlimpseColors.primary.withOpacity(0.2),
                  backgroundImage: pending.revieweePhotoUrl != null
                      ? NetworkImage(pending.revieweePhotoUrl!)
                      : null,
                  child: pending.revieweePhotoUrl == null
                      ? Text(
                          pending.revieweeName[0].toUpperCase(),
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: GlimpseColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pending.revieweeName,
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: GlimpseColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pending.isOwnerReview
                            ? 'Participante do evento'
                            : 'Criador do evento',
                        style: GoogleFonts.getFont(
                          FONT_PLUS_JAKARTA_SANS,
                          fontSize: 13,
                          color: GlimpseColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Prazo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUrgent
                    ? GlimpseColors.error.withOpacity(0.1)
                    : GlimpseColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUrgent ? Icons.warning_amber : Icons.access_time,
                    size: 16,
                    color: isUrgent ? GlimpseColors.error : GlimpseColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    daysRemaining == 0
                        ? 'Expira hoje!'
                        : daysRemaining == 1
                            ? 'Expira amanhã'
                            : 'Expira em $daysRemaining dias',
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isUrgent ? GlimpseColors.error : GlimpseColors.warning,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Botões
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTapDismiss,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Descartar',
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GlimpseColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: onTapEvaluate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlimpseColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Avaliar',
                          style: GoogleFonts.getFont(
                            FONT_PLUS_JAKARTA_SANS,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
