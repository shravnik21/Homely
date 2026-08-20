import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/models/review.dart';
import 'package:homely_app/services/booking_service.dart';
import 'package:homely_app/services/review_service.dart';
import 'package:homely_app/screens/guest/review_prompt_screen.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/utils/network_retry.dart';
import 'package:homely_app/widgets/star_rating.dart';

class _MyReviewsData {
  final List<Review> reviews;
  final List<Booking> reviewable;
  const _MyReviewsData({required this.reviews, required this.reviewable});
}

/// "Your reviews" - every review the current guest has posted, plus
/// any completed stays that are still eligible for one so they can
/// post more from right here, not just via the notification prompt.
/// Reachable from ProfileScreen, and also offered as a next step
/// right after posting a review from NotificationsScreen.
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final ReviewService _reviewService = ReviewService();
  final BookingService _bookingService = BookingService();
  late Future<_MyReviewsData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = withRetry(() async {
        final results = await Future.wait([
          _reviewService.getReviewsByCurrentUser(),
          _bookingService.getUserBookings(),
        ]);
        final reviews = results[0] as List<Review>;
        final bookings = results[1] as List<Booking>;

        final reviewedBookingIds = reviews.map((r) => r.bookingId).toSet();
        final reviewable = bookings.where((b) {
          if (b.status == 'cancelled') return false;
          if (b.isUpcoming) return false; // not checked out yet
          return !reviewedBookingIds.contains(b.id);
        }).toList();

        return _MyReviewsData(reviews: reviews, reviewable: reviewable);
      });
    });
  }

  Future<void> _writeReview(Booking booking) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReviewPromptScreen(booking: booking)),
    );
    if (submitted == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        title: const Text(
          'Your Reviews',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.dark),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<_MyReviewsData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        friendlyError(snapshot.error!,
                            fallback: 'Could not load your reviews.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data!;
            if (data.reviews.isEmpty && data.reviewable.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  if (data.reviewable.isNotEmpty) ...[
                    const Text('Stays you can review',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.dark)),
                    const SizedBox(height: 4),
                    const Text(
                      "You've completed these stays - share how they went.",
                      style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                    ),
                    const SizedBox(height: 12),
                    for (final booking in data.reviewable) ...[
                      _buildReviewableCard(booking),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),
                  ],
                  if (data.reviews.isNotEmpty) ...[
                    Text('Posted (${data.reviews.length})',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.dark)),
                    const SizedBox(height: 12),
                    for (final review in data.reviews) ...[
                      _buildReviewCard(review),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReviewableCard(Booking booking) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: booking.coverImage,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.placeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(booking.checkIn)} - ${_formatDate(booking.checkOut)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _writeReview(booking),
            child: const Text('Write', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Review review) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: review.placeCoverImage != null
                ? CachedNetworkImage(
                    imageUrl: review.placeCoverImage!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 52,
                    height: 52,
                    color: AppColors.lightGrey,
                    child: const Icon(Icons.home_rounded, color: AppColors.grey),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.placeTitle ?? 'Listing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StarRatingDisplay(rating: review.rating.toDouble(), size: 14),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(review.createdAt),
                      style: const TextStyle(fontSize: 11, color: AppColors.grey),
                    ),
                  ],
                ),
                if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    review.comment!.trim(),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.dark, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.lightGrey, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.star_outline_rounded, size: 34, color: AppColors.grey),
            ),
            const SizedBox(height: 16),
            const Text("You haven't reviewed a stay yet",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Once you complete a stay, you can leave a review for it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 13),
            ),
          ],
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
