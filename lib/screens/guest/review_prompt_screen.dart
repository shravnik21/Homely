import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/screens/guest/write_review_screen.dart';
import 'package:homely_app/widgets/primary_button.dart';

/// Shown when a guest taps a "How was your stay?" notification -
/// a friendly confirmation that their stay is complete, before
/// dropping them into the actual rating/comment composer
/// ([WriteReviewScreen]). Keeping this as its own step (rather than
/// jumping straight into the review form) mirrors how Airbnb
/// separates "here's a trip that's ready to review" from the review
/// form itself, and gives a guest an easy "not now" exit that doesn't
/// feel like abandoning a half-filled form.
class ReviewPromptScreen extends StatelessWidget {
  final Booking booking;

  const ReviewPromptScreen({super.key, required this.booking});

  Future<void> _leaveReview(BuildContext context) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WriteReviewScreen(booking: booking)),
    );
    if (submitted == true && context.mounted) {
      // Bubble the result up so NotificationsScreen (and anything
      // else in the stack) knows a review was actually submitted.
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded,
                            size: 36, color: AppColors.primary),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Your stay is complete!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dark),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "You stayed at ${booking.placeTitle} - we'd love to "
                        'hear how it went. Your review helps other guests '
                        'decide, and helps your host too.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.grey, height: 1.4),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18)),
                              child: CachedNetworkImage(
                                imageUrl: booking.coverImage,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.placeTitle,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.dark),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${booking.placeAddress}, ${booking.cityName}',
                                    style: const TextStyle(
                                        fontSize: 12.5, color: AppColors.grey),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded,
                                          size: 14, color: AppColors.grey),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_formatDate(booking.checkIn)} - '
                                        '${_formatDate(booking.checkOut)}',
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.grey,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                text: 'Leave a review',
                onPressed: () => _leaveReview(context),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Not now',
                  style: TextStyle(color: AppColors.grey, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
