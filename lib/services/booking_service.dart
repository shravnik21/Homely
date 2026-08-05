import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/booking.dart';

/// Same service-layer pattern as AuthService/PlacesService - screens
/// never talk to Supabase directly, they call this instead.
class BookingService {
  final _client = SupabaseConfig.client;

  /// Fetches the logged-in user's bookings, each joined with its
  /// place's title, address, city, and cover image - one network
  /// round trip, same nested-select technique as PlacesService.
  Future<List<Booking>> getUserBookings() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('bookings')
        .select(
            '*, places(title, address, city_id, price_per_night, max_guests, cities(name), place_images(image_url, sort_order))')
        .eq('user_id', userId)
        .order('check_in', ascending: false);

    return (response as List)
        .map((row) => Booking.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Marks a booking as cancelled. RLS only allows a user to update
  /// rows where `user_id` matches their own id (see
  /// schema_bookings.sql), so this can never touch someone else's
  /// booking even if the id were guessed.
  Future<void> cancelBooking(String bookingId) async {
    await _client
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', bookingId);
  }

  /// Updates the dates (and recomputed total price) on an existing
  /// booking, for the "Reschedule" option under Manage booking.
  Future<void> rescheduleBooking({
    required String bookingId,
    required DateTime checkIn,
    required DateTime checkOut,
    required num totalPrice,
  }) async {
    await _client.from('bookings').update({
      'check_in': _formatDate(checkIn),
      'check_out': _formatDate(checkOut),
      'total_price': totalPrice,
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
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
