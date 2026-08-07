import 'package:homely_app/config/supabase_config.dart';

/// Figures out which dates are already booked for a place, so the
/// guest-facing date pickers (new booking + reschedule) can grey them
/// out instead of letting a guest pick a range that double-books a
/// listing.
///
/// `bookings`' RLS only lets a user see their OWN rows (see
/// schema_bookings.sql - correctly, since another guest's dates,
/// price, and identity are private) so this can't just
/// `.from('bookings').select()`. It goes through the
/// `get_booked_ranges` Postgres function instead
/// (schema_place_availability.sql), which is `security definer` and
/// intentionally returns nothing but bare date ranges.
class AvailabilityService {
  final _client = SupabaseConfig.client;

  /// Every night that's already booked for [placeId], as a flat set
  /// of dates (time-of-day stripped) for fast `.contains()` lookups
  /// from the calendar widget. The check-out day itself is NOT
  /// included - same convention as any hotel/Airbnb: the next guest
  /// can check in the same day the previous one checks out.
  ///
  /// [excludeBookingId] lets the reschedule flow ignore a booking's
  /// own current dates when computing what's "taken" - without it, a
  /// booking would incorrectly block out its own existing nights.
  Future<Set<DateTime>> getUnavailableDates(
    String placeId, {
    String? excludeBookingId,
  }) async {
    final rows = await _client.rpc('get_booked_ranges', params: {
      'p_place_id': placeId,
      'p_exclude_booking_id': excludeBookingId,
    }) as List;

    final blocked = <DateTime>{};
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final checkIn = DateTime.parse(map['check_in'] as String);
      final checkOut = DateTime.parse(map['check_out'] as String);
      for (var d = checkIn;
          d.isBefore(checkOut);
          d = d.add(const Duration(days: 1))) {
        blocked.add(DateTime(d.year, d.month, d.day));
      }
    }
    return blocked;
  }
}
