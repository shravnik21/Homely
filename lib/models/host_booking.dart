import 'package:homely_app/models/booking.dart';

/// A [Booking] plus the guest's display name - used only on the host
/// side (Host Home, My Listings' bookings, etc). Kept separate from
/// [Booking] itself so the guest-facing MyBookingsScreen doesn't need
/// to care about guest names at all.
class HostBooking {
  final Booking booking;
  final String guestName;

  const HostBooking({required this.booking, required this.guestName});
}
