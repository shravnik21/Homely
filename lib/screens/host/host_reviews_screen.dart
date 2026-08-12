import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/models/review.dart';
import 'package:homely_app/services/listing_service.dart';
import 'package:homely_app/services/review_service.dart';
import 'package:homely_app/screens/host/listing_reviews_screen.dart';
import 'package:homely_app/widgets/error_state_view.dart';
import 'package:homely_app/widgets/star_rating.dart';

class _HostReviewsData {
  final List<Place> listings;
  final List<Review> reviews;
  const _HostReviewsData({required this.listings, required this.reviews});
}

/// Host-side "Reviews" hub, opened from the Host Home dashboard's
/// Reviews card. One row per listing with its average rating +
/// review count, newest-reviewed first - tap a listing to open
/// [ListingReviewsScreen] and read every individual review left on
/// it. This is where a host "manages" reviews per the brief: reviews
/// themselves are read-only (matching Airbnb, a host can't edit or
/// delete a guest's review), so "managing" here means seeing them
/// broken down by listing rather than as one long undifferentiated
/// feed.
class HostReviewsScreen extends StatefulWidget {
  const HostReviewsScreen({super.key});

  @override
  State<HostReviewsScreen> createState() => _HostReviewsScreenState();
}

class _HostReviewsScreenState extends State<HostReviewsScreen> {
  final ListingService _listingService = ListingService();
  final ReviewService _reviewService = ReviewService();
  late Future<_HostReviewsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _dataFuture = Future.wait([
      _listingService.getMyListings(),
      _reviewService.getReviewsForHostListings(),
    ]).then((results) => _HostReviewsData(
          listings: results[0] as List<Place>,
          reviews: results[1] as List<Review>,
        ));
  }

  void _refresh() => setState(_load);

  Future<void> _openListingReviews(Place place) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListingReviewsScreen(place: place)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Reviews',
          style: TextStyle(
              color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: FutureBuilder<_HostReviewsData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                error: snapshot.error!,
                fallbackMessage: 'Could not load your reviews.',
                onRetry: _refresh,
              );
            }

            final listings = snapshot.data?.listings ?? [];
            final reviews = snapshot.data?.reviews ?? [];

            final reviewsByPlace = <String, List<Review>>{};
            for (final review in reviews) {
              (reviewsByPlace[review.placeId] ??= []).add(review);
            }

            // Listings with at least one review first (most-reviewed
            // first), then unreviewed listings - so a host's best-
            // performing properties surface at the top instead of
            // being buried under brand new, empty-review listings.
            final sorted = [...listings]..sort((a, b) {
                final countA = reviewsByPlace[a.id]?.length ?? 0;
                final countB = reviewsByPlace[b.id]?.length ?? 0;
                return countB.compareTo(countA);
              });

            final overallSummary = RatingSummary.fromReviews(reviews);

            if (listings.isEmpty) {
              return _buildEmptyState(
                "You don't have any listings yet. Once guests complete a "
                "stay, their reviews will show up here.",
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (!overallSummary.isEmpty) ...[
                  _buildOverallCard(overallSummary),
                  const SizedBox(height: 20),
                ],
                ...sorted.map((place) {
                  final placeReviews = reviewsByPlace[place.id] ?? [];
                  final summary = RatingSummary.fromReviews(placeReviews);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ListingRatingTile(
                      place: place,
                      summary: summary,
                      onTap: () => _openListingReviews(place),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOverallCard(RatingSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text(
            summary.formatted,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarRatingDisplay(
                rating: summary.average,
                size: 16,
                emptyColor: Colors.white24,
              ),
              const SizedBox(height: 4),
              Text(
                'Overall rating · ${summary.count} review${summary.count == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.4),
        ),
      ),
    );
  }
}

class _ListingRatingTile extends StatelessWidget {
  final Place place;
  final RatingSummary summary;
  final VoidCallback onTap;

  const _ListingRatingTile({
    required this.place,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: place.coverImage,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  width: 60,
                  height: 60,
                  color: AppColors.white,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: AppColors.grey, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.dark),
                  ),
                  const SizedBox(height: 5),
                  if (summary.isEmpty)
                    const Text(
                      'No reviews yet',
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    )
                  else
                    Row(
                      children: [
                        StarRatingDisplay(rating: summary.average, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${summary.formatted} · ${summary.count} review${summary.count == 1 ? '' : 's'}',
                          style: const TextStyle(color: AppColors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey),
          ],
        ),
      ),
    );
  }
}
