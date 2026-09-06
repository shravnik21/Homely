import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/models/review.dart';
import 'package:homely_app/services/review_service.dart';
import 'package:homely_app/widgets/error_state_view.dart';
import 'package:homely_app/widgets/review_tile.dart';
import 'package:homely_app/widgets/star_rating.dart';

/// Host-facing detail view for one listing's reviews - opened from
/// [HostReviewsScreen]'s per-listing summary, or directly from
/// [ListingManageScreen]'s "View Reviews" action tile. Read-only:
/// hosts see ratings and feedback but (matching the brief) don't get
/// an edit/delete/respond action here, same as a guest's own review
/// is immutable once submitted.
class ListingReviewsScreen extends StatefulWidget {
  final Place place;

  const ListingReviewsScreen({super.key, required this.place});

  @override
  State<ListingReviewsScreen> createState() => _ListingReviewsScreenState();
}

class _ListingReviewsScreenState extends State<ListingReviewsScreen> {
  final ReviewService _reviewService = ReviewService();
  late Future<List<Review>> _reviewsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _reviewsFuture = _reviewService.getReviewsForPlace(widget.place.id);
  }

  void _refresh() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        centerTitle: true,
        title: Text(
          widget.place.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Review>>(
          future: _reviewsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                error: snapshot.error!,
                fallbackMessage: 'Could not load reviews.',
                onRetry: _refresh,
              );
            }

            final reviews = snapshot.data ?? [];
            final summary = RatingSummary.fromReviews(reviews);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _buildSummaryHeader(summary),
                const SizedBox(height: 24),
                if (reviews.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      "No reviews yet. They'll show up here once guests "
                      "complete a stay and leave feedback.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.grey, fontSize: 13),
                    ),
                  )
                else
                  ...List.generate(reviews.length, (index) {
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: index == reviews.length - 1 ? 0 : 20),
                      child: ReviewTile(review: reviews[index]),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(RatingSummary summary) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            summary.isEmpty ? '—' : summary.formatted,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarRatingDisplay(rating: summary.average, size: 16),
              const SizedBox(height: 3),
              Text(
                '${summary.count} review${summary.count == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
