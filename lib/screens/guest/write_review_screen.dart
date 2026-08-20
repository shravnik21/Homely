import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/services/review_service.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';
import 'package:homely_app/widgets/star_rating.dart';

/// Opened from [BookingDetailScreen]'s "Leave a review" CTA once a
/// stay is completed. 5-star rating selector + optional written
/// feedback, matching Airbnb's own guest review composer.
///
/// Pops with `true` on a successful submit (same
/// Navigator.pop(true)-refreshes-the-caller pattern used across the
/// app - e.g. ListingManageScreen, BookingDetailScreen) so the
/// screen behind it can refresh without an extra Supabase round trip.
class WriteReviewScreen extends StatefulWidget {
  final Booking booking;

  const WriteReviewScreen({super.key, required this.booking});

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final ReviewService _reviewService = ReviewService();
  final AuthService _authService = AuthService();
  final TextEditingController _commentController = TextEditingController();

  int _rating = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String get _reviewerName {
    final name = _authService.currentUser?.userMetadata?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return 'Guest';
    return name.trim();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _reviewService.submitReview(
        bookingId: widget.booking.id,
        placeId: widget.booking.placeId,
        reviewerName: _reviewerName,
        rating: _rating,
        comment: _commentController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback!')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Same pattern as booking_screen.dart's BookingConflictException
      // handling - a DuplicateReviewException is already
      // user-friendly on its own, so show it directly instead of
      // masking it behind the generic fallback.
      final isDuplicate = e is DuplicateReviewException;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDuplicate
              ? e.toString()
              : friendlyError(e, fallback: 'Could not submit your review.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Airbnb-style label under the stars that updates as you pick a
  // rating, so the number never feels like the only feedback.
  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Not great';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent';
      default:
        return 'Tap to rate';
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
        title: const Text('Write a review'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              widget.booking.placeTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.booking.placeAddress}, ${widget.booking.cityName}',
              style: const TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            const Center(
              child: Text(
                'How was your stay?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dark,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: StarRatingInput(
                rating: _rating,
                onChanged: (value) => setState(() => _rating = value),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _ratingLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey,
                ),
              ),
            ),
            const SizedBox(height: 32),
            CustomTextField(
              controller: _commentController,
              label: 'Tell future guests about your stay (optional)',
              hint: 'What did you love? Anything hosts should know?',
              maxLines: 6,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              text: 'Submit review',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
