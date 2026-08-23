import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/app_notification.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/services/host_listings_service.dart';

/// Host-side mirror of NotificationsService, reading/writing the same
/// `notifications` table - a host is just another `auth.users` row,
/// so no separate table is needed.
///
/// Five types are entirely trigger-driven server-side and this
/// service only ever READS them: host_new_booking,
/// host_booking_cancelled, host_booking_rescheduled, new_review (see
/// schema_host_notifications.sql), and new_message (see
/// schema_message_notifications.sql - already generic across guest
/// and host recipients).
///
/// One type is time-based rather than event-based, so - same as the
/// guest side - [generateTimeBasedNotifications] creates it lazily on
/// the client, called whenever the host opens their Notifications
/// screen: checkin_pin_reminder, a one-shot nudge for a host whose
/// upcoming guest is checking into a smart-lock listing and hasn't
/// been sent the door code yet.
class HostNotificationsService {
  final _client = SupabaseConfig.client;
  final HostBookingsService _bookingsService = HostBookingsService();
  final HostListingsService _listingsService = HostListingsService();

  String? get _hostId => _client.auth.currentUser?.id;

  /// All of the current host's notifications, newest first.
  Future<List<AppNotification>> getNotifications() async {
    final hostId = _hostId;
    if (hostId == null) return [];

    final response = await _client
        .from('notifications')
        .select()
        .eq('user_id', hostId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => AppNotification.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Cheap unread count for the badge on Host Home's bell icon.
  Future<int> getUnreadCount() async {
    final hostId = _hostId;
    if (hostId == null) return 0;

    final response = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', hostId)
        .eq('is_read', false);
    return (response as List).length;
  }

  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  Future<void> markAllAsRead() async {
    final hostId = _hostId;
    if (hostId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', hostId)
        .eq('is_read', false);
  }

  /// One-shot "send the door code" reminder for any upcoming,
  /// non-cancelled booking on a smart-lock listing whose check-in is
  /// tomorrow or today and hasn't been reminded about yet. A single
  /// existence check (like checkin_log_reminder on the guest side),
  /// not a milestone ladder like checkin_reminder - one well-timed
  /// nudge the day before is enough for this one.
  Future<void> generateTimeBasedNotifications() async {
    final hostId = _hostId;
    if (hostId == null) return;

    final results = await Future.wait([
      _bookingsService.getBookingsForMyListings(),
      _listingsService.getMyListings(),
      getNotifications(),
    ]);
    final bookings = results[0] as List<HostBooking>;
    final listings = results[1] as List<Place>;
    final existing = results[2] as List<AppNotification>;

    final smartLockPlaceIds = {
      for (final place in listings)
        if (place.checkinMethod == 'smart_lock') place.id,
    };
    if (smartLockPlaceIds.isEmpty) return;

    final existingPinReminders = {
      for (final n in existing)
        if (n.bookingId != null && n.type == 'checkin_pin_reminder')
          n.bookingId,
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rows = <Map<String, dynamic>>[];

    for (final hostBooking in bookings) {
      final booking = hostBooking.booking;
      if (booking.status == 'cancelled') continue;
      if (!smartLockPlaceIds.contains(booking.placeId)) continue;
      if (existingPinReminders.contains(booking.id)) continue;

      final checkIn = DateTime(
          booking.checkIn.year, booking.checkIn.month, booking.checkIn.day);
      final daysToCheckIn = checkIn.difference(today).inDays;
      if (daysToCheckIn > 1 || daysToCheckIn < 0) continue;

      rows.add({
        'user_id': hostId,
        'type': 'checkin_pin_reminder',
        'title':
            daysToCheckIn == 0 ? "Send today's door code" : "Send tomorrow's door code",
        'body': 'Make sure ${hostBooking.guestName} has the smart lock code '
            'for ${booking.placeTitle} before they check in '
            '${daysToCheckIn == 0 ? 'today' : 'tomorrow'}.',
        'booking_id': booking.id,
        'place_id': booking.placeId,
        'milestone_days': null,
      });
    }

    if (rows.isEmpty) return;

    // Best-effort, same reasoning as the guest-side service - a
    // failed pass just means this is retried next time the screen
    // opens, and a 23505 duplicate-key error would only happen from
    // a genuine race the existence check above already makes
    // vanishingly unlikely.
    try {
      await _client.from('notifications').insert(rows);
    } catch (_) {}
  }

  /// Fetches the single [HostBooking] a notification points to, so
  /// HostNotificationsScreen can push straight into
  /// HostBookingDetailScreen (which needs guest contact info
  /// attached, not just a bare Booking).
  Future<HostBooking?> getHostBookingById(String bookingId) async {
    if (_hostId == null) return null;
    final all = await _bookingsService.getBookingsForMyListings();
    for (final hostBooking in all) {
      if (hostBooking.booking.id == bookingId) return hostBooking;
    }
    return null;
  }
}
