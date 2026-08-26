import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/booking.dart';

/// Thrown when the database rejects a booking insert/update because
/// it would overlap another active booking for the same place (see
/// schema_no_overlapping_bookings.sql's EXCLUDE constraint) - the
/// last-resort case where two guests both had the calendar open on
/// the same free dates and one of them lost the race. Distinct from
/// a generic Exception so calling screens can show a specific,
/// actionable message instead of a raw Postgres error string.
class BookingConflictException implements Exception {
  final String message;
  const BookingConflictException([
    this.message = 'Those dates were just booked by someone else. '
        'Please choose different dates.',
  ]);

  @override
  String toString() => message;
}

/// Same service-layer pattern as AuthService/PlacesService - screens
/// never talk to Supabase directly, they call this instead.
class BookingService {
  final _client = SupabaseConfig.client;

  /// Postgres' code for a violated EXCLUDE constraint - the one
  /// no_overlapping_bookings raises when a new/updated booking
  /// overlaps an existing active one for the same place.
  static const _exclusionViolationCode = '23P01';

  /// Re-throws [e] as a [BookingConflictException] if it's the
  /// overlapping-dates constraint from schema_no_overlapping_bookings.sql,
  /// otherwise re-throws it unchanged so genuine errors (network,
  /// auth, etc) still surface as themselves.
  Never _rethrowMapped(Object e) {
    if (e is PostgrestException && e.code == _exclusionViolationCode) {
      throw const BookingConflictException();
    }
    throw e;
  }

  /// Fetches the logged-in user's bookings, each joined with its
  /// place's title, address, city, and cover image - one network
  /// round trip, same nested-select technique as PlacesService.
  /// Excludes anything the guest has swiped away via [hideBooking] -
  /// that's a per-guest flag, so it has no effect on what the host
  /// sees for the same booking.
  Future<List<Booking>> getUserBookings() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('bookings')
        .select(
            '*, places(title, address, city_id, price_per_night, max_guests, host_id, host_public_info(full_name), cancellation_policy_type, cancellation_flexible_free_days, cancellation_flexible_fee_percent, cities(name), place_images(image_url, sort_order))')
        .eq('user_id', userId)
        .eq('hidden_by_guest', false)
        .order('check_in', ascending: false);

    return (response as List)
        .map((row) => Booking.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Removes a booking from the GUEST's own bookings list only (see
  /// schema_hide_bookings.sql) - a soft delete, not a cancellation and
  /// not visible to the host. Intended for past/cancelled bookings
  /// the guest just wants off their list; the caller
  /// (MyBookingsScreen) is responsible for only offering this on
  /// bookings where `!booking.isUpcoming`.
  Future<void> hideBooking(String bookingId) async {
    await _client
        .from('bookings')
        .update({'hidden_by_guest': true})
        .eq('id', bookingId);
  }

  /// Marks a booking as cancelled and records what CancellationPolicy
  /// charged for it - [fee]/[refund] are computed by the caller
  /// (CancellationDetailScreen shows the same numbers to the guest
  /// before they confirm) and stored as-is so they can't drift later.
  /// RLS only allows a user to update rows where `user_id` matches
  /// their own id (see schema_bookings.sql), so this can never touch
  /// someone else's booking even if the id were guessed.
  Future<void> cancelBooking(
    String bookingId, {
    required num fee,
    required num refund,
  }) async {
    await _client.from('bookings').update({
      'status': 'cancelled',
      'cancellation_fee': fee,
      'refund_amount': refund,
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bookingId);
  }

  /// Updates the dates (and recomputed total price) on an existing
  /// booking, for the "Reschedule" option under Manage booking.
  /// [previousCheckIn]/[previousCheckOut] are the dates being
  /// replaced - stored alongside a fresh `rescheduled_at` timestamp
  /// (see schema_reschedule_tracking.sql) purely so the host
  /// dashboard's "Booking updates" card can show what changed,
  /// mirroring how cancelBooking() records cancellation_fee/
  /// refund_amount for its own card.
  Future<void> rescheduleBooking({
    required String bookingId,
    required DateTime checkIn,
    required DateTime checkOut,
    required num totalPrice,
    required DateTime previousCheckIn,
    required DateTime previousCheckOut,
  }) async {
    try {
      await _client.from('bookings').update({
        'check_in': _formatDate(checkIn),
        'check_out': _formatDate(checkOut),
        'total_price': totalPrice,
        'previous_check_in': _formatDate(previousCheckIn),
        'previous_check_out': _formatDate(previousCheckOut),
        'rescheduled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      _rethrowMapped(e);
    }
  }

  /// Marks a booking as checked-in (see schema_checked_in.sql) - a
  /// single tap, no fee/quote to compute first like cancel/reschedule
  /// have. RLS only allows a user to update rows where `user_id`
  /// matches their own id, same guarantee cancelBooking() relies on.
  Future<void> confirmCheckIn(String bookingId) async {
    await _client.from('bookings').update({
      'checked_in_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bookingId);
  }

  /// Inserts the booking row and returns its generated `id`, so the
  /// caller can show a booking reference on the confirmation screen.
  Future<String> createBooking({
    required String placeId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
    required num totalPrice,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to book a place.');
    }

    // Dates are sent as 'YYYY-MM-DD' strings - Postgres' `date` column
    // doesn't need time-of-day, and this avoids timezone mismatches
    // between the device and the server.
    // `.select('id').single()` asks PostgREST to hand back the row it
    // just inserted (instead of the default empty response) so we can
    // read the new booking's id straight away.
    try {
      final row = await _client
          .from('bookings')
          .insert({
            'user_id': userId,
            'place_id': placeId,
            'check_in': _formatDate(checkIn),
            'check_out': _formatDate(checkOut),
            'guests': guests,
            'total_price': totalPrice,
          })
          .select('id')
          .single();

      return row['id'] as String;
    } catch (e) {
      _rethrowMapped(e);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
