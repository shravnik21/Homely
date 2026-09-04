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

/// What cancel_booking() actually charged/refunded, computed
/// server-side (see schema_secure_bookings.sql) - the caller no
/// longer sends fee/refund, it just reads back what was applied.
class CancelBookingResult {
  final num fee;
  final num refund;
  final DateTime cancelledAt;

  const CancelBookingResult({
    required this.fee,
    required this.refund,
    required this.cancelledAt,
  });
}

/// What reschedule_booking() actually set the new total to,
/// recomputed server-side from the listing's real price_per_night -
/// the caller no longer sends totalPrice.
class RescheduleBookingResult {
  final DateTime checkIn;
  final DateTime checkOut;
  final num totalPrice;
  final DateTime rescheduledAt;

  const RescheduleBookingResult({
    required this.checkIn,
    required this.checkOut,
    required this.totalPrice,
    required this.rescheduledAt,
  });
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

  /// Marks a booking as cancelled via the cancel_booking() Postgres
  /// function (see schema_secure_bookings.sql), which recomputes the
  /// fee/refund itself from the listing's real cancellation policy
  /// and the booking's real check-in date - a guest can no longer
  /// just pass in whatever fee/refund numbers they like. The
  /// function only touches rows where `user_id` matches the caller's
  /// own id, same guarantee the old direct-update version relied on.
  /// Returns what was actually applied, for the caller to show/store.
  Future<CancelBookingResult> cancelBooking(String bookingId) async {
    try {
      final row = await _client.rpc(
        'cancel_booking',
        params: {'p_booking_id': bookingId},
      ) as Map<String, dynamic>;

      return CancelBookingResult(
        fee: (row['cancellation_fee'] as num?) ?? 0,
        refund: (row['refund_amount'] as num?) ?? 0,
        cancelledAt: DateTime.parse(row['cancelled_at'] as String),
      );
    } catch (e) {
      _rethrowMapped(e);
    }
  }

  /// Updates the dates on an existing booking via the
  /// reschedule_booking() Postgres function, for the "Reschedule"
  /// option under Manage booking. The function recomputes total_price
  /// itself from the listing's real price_per_night (never trusting
  /// a client-supplied total) and captures the old dates as
  /// previous_check_in/out server-side before overwriting them - the
  /// caller no longer needs to pass either. Still surfaces as a
  /// BookingConflictException if the new dates overlap someone else's
  /// stay, exactly as before (schema_no_overlapping_bookings.sql's
  /// EXCLUDE constraint still applies to the function's own UPDATE).
  Future<RescheduleBookingResult> rescheduleBooking({
    required String bookingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) async {
    try {
      final row = await _client.rpc(
        'reschedule_booking',
        params: {
          'p_booking_id': bookingId,
          'p_check_in': _formatDate(checkIn),
          'p_check_out': _formatDate(checkOut),
        },
      ) as Map<String, dynamic>;

      return RescheduleBookingResult(
        checkIn: DateTime.parse(row['check_in'] as String),
        checkOut: DateTime.parse(row['check_out'] as String),
        totalPrice: (row['total_price'] as num?) ?? 0,
        rescheduledAt: DateTime.parse(row['rescheduled_at'] as String),
      );
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

  // Booking creation itself no longer lives here - `bookings` has no
  // client-facing insert policy anymore (see
  // schema_secure_bookings.sql). A booking can now only be created by
  // PaymentService.verifyAndCreateBooking(), which requires a
  // verified Razorpay payment signature first. See BookingScreen.

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
