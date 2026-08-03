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
  /// check-in first, each with the guest's name attached. One query
  /// for the bookings (`places!inner(...)` + `.eq('places.host_id', ...)`
  /// does the "only my listings" filtering server-side) plus one
  /// follow-up query to resolve guest names, since `bookings.user_id`
  /// and `profiles.id` aren't linked by a foreign key PostgREST can
  /// auto-embed across.
  Future<List<HostBooking>> getBookingsForMyListings() async {
    final hostId = _client.auth.currentUser?.id;
    if (hostId == null) return [];

    final response = await _client
        .from('bookings')
        .select(
            '*, places!inner(title, address, city_id, host_id, cities(name), place_images(image_url, sort_order))')
        .eq('places.host_id', hostId)
        .order('check_in', ascending: false);

    final bookings = (response as List)
        .map((row) => Booking.fromMap(row as Map<String, dynamic>))
        .toList();

    if (bookings.isEmpty) return [];

    final guestIds = bookings.map((b) => b.userId).toSet().toList();
    final namesById = <String, String>{};
    try {
      final profileRows = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', guestIds);
      for (final row in profileRows as List) {
        final name = row['full_name'] as String?;
        namesById[row['id'] as String] =
            (name != null && name.trim().isNotEmpty) ? name.trim() : 'Guest';
      }
    } catch (_) {
      // Non-critical - bookings still render, just with a generic
      // "Guest" label instead of a real name.
    }

    return bookings
        .map((b) => HostBooking(
              booking: b,
              guestName: namesById[b.userId] ?? 'Guest',
            ))
        .toList();
  }
}
