import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/review.dart';

/// Thrown when a guest tries to review the same BOOKING a second
/// time - the one duplicate `reviews` genuinely doesn't allow (the
/// unique constraint on booking_id in schema_reviews.sql). Distinct
/// from a generic Exception, same reasoning as BookingConflictException
/// in booking_service.dart, so WriteReviewScreen can show this exact
/// message instead of a raw Postgres error string.
class DuplicateReviewException implements Exception {
  final String message;
  const DuplicateReviewException([this.message = "You've already reviewed this stay."]);

  @override
  String toString() => message;
}

/// Same service-layer pattern as BookingService/PlacesService -
/// screens never talk to Supabase directly for reviews, they call
/// this instead.
class ReviewService {
  final _client = SupabaseConfig.client;

  /// Postgres' code for a violated unique constraint - the one
  /// `reviews_booking_id_key` raises if a booking is somehow reviewed
  /// twice (the UI already prevents this via [hasReviewedBooking],
  /// this is just the last-resort server-side guarantee).
  static const _uniqueViolationCode = '23505';

  /// All reviews for one place, newest first - used by
  /// PlaceDetailScreen (guest-facing) and ListingReviewsScreen
  /// (host-facing, same query - RLS just widens which listings a
  /// host can see beyond "published").
  Future<List<Review>> getReviewsForPlace(String placeId) async {
    final response = await _client
        .from('reviews')
        .select()
        .eq('place_id', placeId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Review.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Every review across every listing the current host owns, in one
  /// round trip - used by HostReviewsScreen to build the per-listing
  /// average-rating overview without querying place-by-place.
  Future<List<Review>> getReviewsForHostListings() async {
    final hostId = _client.auth.currentUser?.id;
    if (hostId == null) return [];

    final response = await _client
        .from('reviews')
        .select('*, places!inner(host_id)')
        .eq('places.host_id', hostId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Review.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Every review the CURRENT guest has ever written, newest first,
  /// each joined with its place's title/cover photo - powers
  /// MyReviewsScreen ("Your reviews"). Allowed by the
  /// "Reviewers can view their own reviews" RLS policy
  /// (schema_reviews.sql), which is scoped to auth.uid() = reviewer_id
  /// regardless of a listing's current published/paused status.
  Future<List<Review>> getReviewsByCurrentUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('reviews')
        .select(
            '*, places(title, place_images(image_url, sort_order))')
        .eq('reviewer_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Review.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Whether the current user has already reviewed this booking -
  /// checked before showing the "Leave a review" CTA so a guest can
  /// never even attempt a duplicate.
  Future<bool> hasReviewedBooking(String bookingId) async {
    final review = await getReviewForBooking(bookingId);
    return review != null;
  }

  /// The review for one specific booking, if it exists - used to show
  /// "Your review" (rating + comment) on the booking details screen
  /// once a guest has already reviewed that stay.
  Future<Review?> getReviewForBooking(String bookingId) async {
    final response = await _client
        .from('reviews')
        .select()
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (response == null) return null;
    return Review.fromMap(response);
  }

  /// Inserts the review row. [reviewerName] is captured from the
  /// current user's profile/auth metadata by the caller (WriteReviewScreen)
  /// and stored directly on the row - see schema_reviews.sql's top
  /// comment for why. RLS (schema_reviews.sql) independently re-checks
  /// that this booking is the caller's own, confirmed, and already
  /// checked out - so this can never succeed for a booking that isn't
  /// genuinely eligible, even if a client-side bug let it be attempted.
  Future<void> submitReview({
    required String bookingId,
    required String placeId,
    required String reviewerName,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to leave a review.');
    }

    final trimmedComment = comment?.trim();
    try {
      await _client.from('reviews').insert({
        'booking_id': bookingId,
        'place_id': placeId,
        'reviewer_id': userId,
        'reviewer_name': reviewerName,
        'rating': rating,
        'comment': (trimmedComment == null || trimmedComment.isEmpty)
            ? null
            : trimmedComment,
      });
    } catch (e) {
      if (e is PostgrestException && e.code == _uniqueViolationCode) {
        throw const DuplicateReviewException();
      }
      rethrow;
    }
  }
}
