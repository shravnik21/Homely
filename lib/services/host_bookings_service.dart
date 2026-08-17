import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/models/host_booking.dart';

/// Read-side service for the bookings a host's guests have made,
/// across ALL of that host's listings. Mirrors BookingService's
/// pattern (screens never touch Supabase directly) but scoped to the
/// host rather than the guest.
class HostBookingsService {
  final _client = SupabaseConfig.client;

  /// Every booking made on any of the current host's listings, newest
  /// check-in first, each with the guest's contact info attached. One
  /// query for the bookings (`places!inner(...)` +
  /// `.eq('places.host_id', ...)` does the "only my listings"
  /// filtering server-side) plus one follow-up query to resolve guest
  /// profiles, since `bookings.user_id` and `profiles.id` aren't
  /// linked by a foreign key PostgREST can auto-embed across.
  /// Excludes anything the host has swiped away via [hideBooking] -
  /// that's a per-host flag (schema_hide_bookings.sql), so it has no
  /// effect on what the guest sees for the same booking.
  Future<List<HostBooking>> getBookingsForMyListings() async {
    final hostId = _client.auth.currentUser?.id;
    if (hostId == null) return [];

    final response = await _client
        .from('bookings')
        .select(
            '*, places!inner(title, address, city_id, host_id, cities(name), place_images(image_url, sort_order))')
        .eq('places.host_id', hostId)
        .eq('hidden_by_host', false)
        .order('check_in', ascending: false);

    final rows = (response as List).cast<Map<String, dynamic>>();
    final bookings = rows.map((row) => Booking.fromMap(row)).toList();
    final notesByBookingId = <String, String?>{
      for (final row in rows) row['id'] as String: row['host_notes'] as String?,
    };

    if (bookings.isEmpty) return [];

    final guestIds = bookings.map((b) => b.userId).toSet().toList();
    final profileById = <String, Map<String, dynamic>>{};
    try {
      final profileRows = await _client
          .from('profiles')
          .select('id, full_name, email, phone, avatar_url')
          .inFilter('id', guestIds);
      for (final row in profileRows as List) {
        profileById[row['id'] as String] = row as Map<String, dynamic>;
      }
    } catch (_) {
      // Non-critical - bookings still render, just with a generic
      // "Guest" label instead of real contact info.
    }

    String nameFor(String userId) {
      final name = profileById[userId]?['full_name'] as String?;
      return (name != null && name.trim().isNotEmpty) ? name.trim() : 'Guest';
    }

    return bookings
        .map((b) => HostBooking(
              booking: b,
              guestName: nameFor(b.userId),
              guestEmail: profileById[b.userId]?['email'] as String?,
              guestPhone: profileById[b.userId]?['phone'] as String?,
              guestAvatarUrl: profileById[b.userId]?['avatar_url'] as String?,
              hostNotes: notesByBookingId[b.id],
            ))
        .toList();
  }

  /// Saves (or clears, if [notes] is null/empty) the host's private
  /// note for one booking. Only succeeds for bookings on a listing
  /// the current host owns - enforced by the RLS policy added in
  /// schema_host_booking_notes.sql.
  Future<void> updateHostNotes({
    required String bookingId,
    required String? notes,
  }) async {
    final trimmed = notes?.trim();
    await _client
        .from('bookings')
        .update({'host_notes': (trimmed == null || trimmed.isEmpty) ? null : trimmed})
        .eq('id', bookingId);
  }

  /// Removes a booking from the HOST's own bookings list only (see
  /// schema_hide_bookings.sql) - a soft delete, not visible to the
  /// guest and doesn't touch the booking itself. Intended for
  /// past/cancelled bookings the host just wants off their list; the
  /// caller (HostBookingsScreen) is responsible for only offering
  /// this on bookings where `!booking.isUpcoming`.
  Future<void> hideBooking(String bookingId) async {
    await _client
        .from('bookings')
        .update({'hidden_by_host': true})
        .eq('id', bookingId);
  }
}
