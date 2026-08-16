import 'package:homely_app/config/supabase_config.dart';

/// Figures out which dates are already unavailable for a place - both
/// guest-booked nights AND dates the host has manually blocked off
/// (see schema_blocked_dates.sql) - so the guest-facing date pickers
/// (new booking + reschedule) can grey both out identically. From the
/// guest's point of view there's no difference between the two; a
/// date is either bookable or it isn't.
///
/// `bookings`' RLS only lets a user see their OWN rows (see
/// schema_bookings.sql - correctly, since another guest's dates,
/// price, and identity are private) so this can't just
/// `.from('bookings').select()`. It goes through the
/// `get_booked_ranges` Postgres function instead
/// (schema_place_availability.sql), which is `security definer` and
/// intentionally returns nothing but bare date ranges. Host-blocked
/// dates go through the equivalent `get_blocked_dates` function
/// (schema_blocked_dates.sql) for the same reason - `blocked_dates`
/// itself is host-only via RLS.
class AvailabilityService {
  final _client = SupabaseConfig.client;

  /// Every night that's either already booked or blocked by the host
  /// for [placeId], as a flat set of dates (time-of-day stripped) for
  /// fast `.contains()` lookups from the calendar widget. The
  /// check-out day of a booking itself is NOT included - same
  /// convention as any hotel/Airbnb: the next guest can check in the
  /// same day the previous one checks out.
  ///
  /// [excludeBookingId] lets the reschedule flow ignore a booking's
  /// own current dates when computing what's "taken" - without it, a
  /// booking would incorrectly block out its own existing nights.
  Future<Set<DateTime>> getUnavailableDates(
    String placeId, {
    String? excludeBookingId,
  }) async {
    final results = await Future.wait([
      _client.rpc('get_booked_ranges', params: {
        'p_place_id': placeId,
        'p_exclude_booking_id': excludeBookingId,
      }),
      _client.rpc('get_blocked_dates', params: {'p_place_id': placeId}),
    ]);

    final bookedRows = results[0] as List;
    final blockedRows = results[1] as List;

    final unavailable = <DateTime>{};
    for (final row in bookedRows) {
      final map = row as Map<String, dynamic>;
      final checkIn = DateTime.parse(map['check_in'] as String);
      final checkOut = DateTime.parse(map['check_out'] as String);
      for (var d = checkIn;
          d.isBefore(checkOut);
          d = d.add(const Duration(days: 1))) {
        unavailable.add(DateTime(d.year, d.month, d.day));
      }
    }
    for (final row in blockedRows) {
      final map = row as Map<String, dynamic>;
      final date = DateTime.parse(map['date'] as String);
      unavailable.add(DateTime(date.year, date.month, date.day));
    }
    return unavailable;
  }
}
