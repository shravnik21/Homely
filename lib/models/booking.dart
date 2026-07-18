/// Represents one row from `bookings`, joined with its related place
/// (title, address, city, cover image). Mirrors what
/// BookingService.getUserBookings() returns from Supabase.
class Booking {
  final String id;
  final String placeId;
  final String placeTitle;
  final String placeAddress;
  final String cityName;
  final String coverImage;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final num totalPrice;
  final String status; // 'confirmed' | 'cancelled' (from the DB column)

  Booking({
    required this.id,
    required this.placeId,
    required this.placeTitle,
    required this.placeAddress,
    required this.cityName,
    required this.coverImage,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.totalPrice,
    required this.status,
  });

  int get nights => checkOut.difference(checkIn).inDays;

  /// Derived, time-based label - separate from the DB `status` column
  /// (which only tracks confirmed/cancelled). A booking is "Upcoming"
  /// or "Completed" purely based on today's date vs check-out date.
  bool get isUpcoming =>
      status != 'cancelled' && checkOut.isAfter(DateTime.now());

  factory Booking.fromMap(Map<String, dynamic> map) {
    final place = map['places'] as Map<String, dynamic>? ?? {};
    final imagesRaw = (place['place_images'] as List<dynamic>? ?? []);
    imagesRaw.sort((a, b) =>
        (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
    final firstImage = imagesRaw.isNotEmpty
        ? imagesRaw.first['image_url'] as String
        : 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2';

    return Booking(
      id: map['id'] as String,
      placeId: map['place_id'] as String,
      placeTitle: place['title'] as String? ?? 'Place',
      placeAddress: place['address'] as String? ?? '',
      cityName: (place['cities']?['name'] as String?) ?? '',
      coverImage: firstImage,
      checkIn: DateTime.parse(map['check_in'] as String),
      checkOut: DateTime.parse(map['check_out'] as String),
      guests: map['guests'] as int? ?? 1,
      totalPrice: map['total_price'] as num? ?? 0,
      status: map['status'] as String? ?? 'confirmed',
    );
  }
}
