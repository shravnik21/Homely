/// Represents one row from `bookings`, joined with its related place
/// (title, address, city, cover image). Mirrors what
/// BookingService.getUserBookings() returns from Supabase.
class Booking {
  final String id;
  final String userId;
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
  // Needed to recompute the price when a guest reschedules to a
  // different number of nights - not shown directly on the bookings
  // list, only used by the reschedule flow.
  final num pricePerNight;
  final int maxGuests;
  // Set only once a cancellation has actually happened - the fee
  // charged and amount refunded, priced at that moment by
  // CancellationPolicy and then stored as-is (see
  // schema_cancellation_fee.sql) so it doesn't drift if the policy
  // changes later.
  final num? cancellationFee;
  final num? refundAmount;
  final DateTime? cancelledAt;

  Booking({
    required this.id,
    required this.userId,
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
    this.pricePerNight = 0,
    this.maxGuests = 1,
    this.cancellationFee,
    this.refundAmount,
    this.cancelledAt,
  });

  int get nights => checkOut.difference(checkIn).inDays;

  /// Derived, time-based label - separate from the DB `status` column
  /// (which only tracks confirmed/cancelled). A booking is "Upcoming"
  /// or "Completed" purely based on today's date vs check-out date.
  bool get isUpcoming =>
      status != 'cancelled' && checkOut.isAfter(DateTime.now());

  /// Used by the booking-details screen to reflect a reschedule/cancel
  /// immediately without refetching the whole list from Supabase.
  Booking copyWith({
    DateTime? checkIn,
    DateTime? checkOut,
    num? totalPrice,
    String? status,
    num? cancellationFee,
    num? refundAmount,
    DateTime? cancelledAt,
  }) {
    return Booking(
      id: id,
      userId: userId,
      placeId: placeId,
      placeTitle: placeTitle,
      placeAddress: placeAddress,
      cityName: cityName,
      coverImage: coverImage,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      guests: guests,
      totalPrice: totalPrice ?? this.totalPrice,
      status: status ?? this.status,
      pricePerNight: pricePerNight,
      maxGuests: maxGuests,
      cancellationFee: cancellationFee ?? this.cancellationFee,
      refundAmount: refundAmount ?? this.refundAmount,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }

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
      userId: map['user_id'] as String,
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
      pricePerNight: place['price_per_night'] as num? ?? 0,
      maxGuests: place['max_guests'] as int? ?? 1,
      cancellationFee: map['cancellation_fee'] as num?,
      refundAmount: map['refund_amount'] as num?,
      cancelledAt: map['cancelled_at'] != null
          ? DateTime.parse(map['cancelled_at'] as String)
          : null,
    );
  }
}
