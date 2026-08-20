/// Represents one row from `reviews`. `reviewerName` is stored
/// directly on the row rather than joined from `profiles` - see the
/// comment at the top of schema_reviews.sql for why.
class Review {
  final String id;
  final String bookingId;
  final String placeId;
  final String reviewerId;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  // Only populated when fetched via
  // ReviewService.getReviewsByCurrentUser() (which joins `places`) -
  // null for every other query path (getReviewsForPlace,
  // getReviewsForHostListings), where the caller already knows which
  // place it's asking about and doesn't need it repeated per-review.
  final String? placeTitle;
  final String? placeCoverImage;

  Review({
    required this.id,
    required this.bookingId,
    required this.placeId,
    required this.reviewerId,
    required this.reviewerName,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.placeTitle,
    this.placeCoverImage,
  });

  String get reviewerInitial =>
      reviewerName.trim().isNotEmpty ? reviewerName.trim()[0].toUpperCase() : '?';

  factory Review.fromMap(Map<String, dynamic> map) {
    final place = map['places'] as Map<String, dynamic>?;
    String? coverImage;
    if (place != null) {
      final images = place['place_images'] as List?;
      if (images != null && images.isNotEmpty) {
        final sorted = List<Map<String, dynamic>>.from(images)
          ..sort((a, b) =>
              (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
        coverImage = sorted.first['image_url'] as String?;
      }
    }
    return Review(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      placeId: map['place_id'] as String,
      reviewerId: map['reviewer_id'] as String,
      reviewerName: map['reviewer_name'] as String? ?? 'Guest',
      rating: map['rating'] as int? ?? 0,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      placeTitle: place?['title'] as String?,
      placeCoverImage: coverImage,
    );
  }
}

/// Average rating + review count for one place, derived client-side
/// from a `List<Review>` - not its own DB table, just a small helper
/// so screens don't all recompute this by hand.
class RatingSummary {
  final double average;
  final int count;

  const RatingSummary({required this.average, required this.count});

  factory RatingSummary.fromReviews(List<Review> reviews) {
    if (reviews.isEmpty) return const RatingSummary(average: 0, count: 0);
    final total = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    return RatingSummary(
      average: total / reviews.length,
      count: reviews.length,
    );
  }

  bool get isEmpty => count == 0;

  /// e.g. "4.8" - always one decimal place, matching Airbnb's format.
  String get formatted => average.toStringAsFixed(1);
}
