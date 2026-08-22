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
  // The listing's host - present whenever the query joins
  // places/host_public_info (getUserBookings does; the host-side
  // query doesn't need it, since the host already knows they're the
  // host). Powers the guest-side "Message host" action.
  final String? hostId;
  final String? hostName;
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
  // Set only once a reschedule has actually happened - mirrors the
  // cancellation fields above so the host dashboard's "Booking
  // updates" card can tell a fresh reschedule apart from a booking
  // that was simply created with these dates, and show what the
  // dates used to be (see schema_reschedule_tracking.sql).
  final DateTime? rescheduledAt;
  final DateTime? previousCheckIn;
  final DateTime? previousCheckOut;
  // Set once the guest taps "I've checked in" (see schema_checked_in.sql)
  // - null until then, never unset afterwards. Distinct from the
  // derived `isUpcoming`/status fields: those track whether the
  // BOOKING is active, this tracks whether the guest has actually
  // confirmed arriving.
  final DateTime? checkedInAt;

  Booking({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.placeTitle,
    required this.placeAddress,
    required this.cityName,
    required this.coverImage,
    this.hostId,
    this.hostName,
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
    this.rescheduledAt,
    this.previousCheckIn,
    this.previousCheckOut,
    this.checkedInAt,
  });

  int get nights => checkOut.difference(checkIn).inDays;

  /// Derived, time-based label - separate from the DB `status` column
  /// (which only tracks confirmed/cancelled). A booking is "Upcoming"
  /// or "Completed" purely based on today's date vs check-out date.
  bool get isUpcoming =>
      status != 'cancelled' && checkOut.isAfter(DateTime.now());

  /// Whether the stay is happening *right now* - today falls between
  /// check-in and check-out inclusive. This is the window in which
  /// "I've checked in" is offered/relevant; before it there's nothing
  /// to confirm yet, after it the stay is over (see [isCompleted]).
  bool get isLive {
    if (status == 'cancelled') return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(checkIn) && !today.isAfter(checkOut);
  }

  /// Mirrors BookingDetailScreen's `_isCompleted` - not cancelled, and
  /// checkout has already passed.
  bool get isCompleted => status != 'cancelled' && !isUpcoming;

  bool get isCheckedIn => checkedInAt != null;

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
    DateTime? rescheduledAt,
    DateTime? previousCheckIn,
    DateTime? previousCheckOut,
    DateTime? checkedInAt,
  }) {
    return Booking(
      id: id,
      userId: userId,
      placeId: placeId,
      placeTitle: placeTitle,
      placeAddress: placeAddress,
      cityName: cityName,
      coverImage: coverImage,
      hostId: hostId,
      hostName: hostName,
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
      rescheduledAt: rescheduledAt ?? this.rescheduledAt,
      previousCheckIn: previousCheckIn ?? this.previousCheckIn,
      previousCheckOut: previousCheckOut ?? this.previousCheckOut,
      checkedInAt: checkedInAt ?? this.checkedInAt,
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
      hostId: place['host_id'] as String?,
      hostName: place['host_public_info']?['full_name'] as String?,
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
      rescheduledAt: map['rescheduled_at'] != null
          ? DateTime.parse(map['rescheduled_at'] as String)
          : null,
      previousCheckIn: map['previous_check_in'] != null
          ? DateTime.parse(map['previous_check_in'] as String)
          : null,
      previousCheckOut: map['previous_check_out'] != null
          ? DateTime.parse(map['previous_check_out'] as String)
          : null,
      checkedInAt: map['checked_in_at'] != null
          ? DateTime.parse(map['checked_in_at'] as String)
          : null,
    );
  }
}
