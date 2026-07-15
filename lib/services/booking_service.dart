import '../config/supabase_config.dart';

/// Same service-layer pattern as AuthService/PlacesService - screens
/// never talk to Supabase directly, they call this instead.
class BookingService {
  final _client = SupabaseConfig.client;

  Future<void> createBooking({
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
    await _client.from('bookings').insert({
      'user_id': userId,
      'place_id': placeId,
      'check_in': _formatDate(checkIn),
      'check_out': _formatDate(checkOut),
      'guests': guests,
      'total_price': totalPrice,
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
