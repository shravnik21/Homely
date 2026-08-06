import 'package:homely_app/models/booking.dart';

/// A [Booking] plus the guest's display info - used only on the host
/// side (Host Home, My Listings' bookings, the booking-detail screen,
/// etc). Kept separate from [Booking] itself so the guest-facing
/// MyBookingsScreen doesn't need to care about any of this at all.
class HostBooking {
  final Booking booking;
  final String guestName;
  final String? guestEmail;
  final String? guestPhone;
  final String? guestAvatarUrl;
  // Free-text, host-only note about this booking (e.g. "asked for
  // early check-in"). Guests never see this - it's saved to the
  // `host_notes` column on `bookings`, editable only by the host who
  // owns the listing (see schema_host_booking_notes.sql).
  final String? hostNotes;

  const HostBooking({
    required this.booking,
    required this.guestName,
    this.guestEmail,
    this.guestPhone,
    this.guestAvatarUrl,
    this.hostNotes,
  });

  String get guestInitial =>
      guestName.trim().isNotEmpty ? guestName.trim()[0].toUpperCase() : '?';

  HostBooking copyWith({
    Booking? booking,
    String? hostNotes,
  }) {
    return HostBooking(
      booking: booking ?? this.booking,
      guestName: guestName,
      guestEmail: guestEmail,
      guestPhone: guestPhone,
      guestAvatarUrl: guestAvatarUrl,
      hostNotes: hostNotes ?? this.hostNotes,
    );
  }
}
