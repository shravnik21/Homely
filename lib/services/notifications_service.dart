import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/app_notification.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/services/booking_service.dart';
import 'package:homely_app/services/review_service.dart';

/// Same service-layer pattern as BookingService/ReviewService -
/// screens never talk to Supabase directly.
///
/// Three notification types (booking_confirmed/cancelled/rescheduled)
/// are entirely trigger-driven server-side (see
/// schema_notifications.sql) - this service only ever READS those.
/// The other four (checkin_reminder, checkin_log_reminder,
/// review_prompt, suggestion) are time-based rather than event-based,
/// and this project has no server-side cron to fire them on a
/// schedule, so [generateTimeBasedNotifications] creates them lazily
/// on the client instead, called once whenever the guest opens the
/// Notifications screen - see that method for how duplicates are
/// avoided.
class NotificationsService {
  final _client = SupabaseConfig.client;
  final BookingService _bookingService = BookingService();
  final ReviewService _reviewService = ReviewService();

  String? get _userId => _client.auth.currentUser?.id;

  /// All of the current guest's notifications, newest first.
  Future<List<AppNotification>> getNotifications() async {
    final userId = _userId;
    if (userId == null) return [];

    final response = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => AppNotification.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Just the unread count - cheap enough to call from the home
  /// screen header for the bell icon's badge without loading the
  /// full list.
  Future<int> getUnreadCount() async {
    final userId = _userId;
    if (userId == null) return 0;

    final response = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return (response as List).length;
  }

  Future<void> markAsRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  Future<void> markAllAsRead() async {
    final userId = _userId;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  /// Generates the time-based notifications that have become due
  /// since the last time this ran:
  ///  - a "days to go" check-in countdown reminder for any confirmed
  ///    upcoming booking, fired at whichever checkpoint (3 days out,
  ///    1 day out, or day-of) it has most recently crossed - so a
  ///    guest who opens the app regularly gets a nudge at each
  ///    checkpoint, and one who only opens it once still gets an
  ///    accurate "X days to go" the first time they do,
  ///  - a one-shot "log your check-in" nudge for any confirmed
  ///    booking whose stay is currently live and hasn't been
  ///    confirmed via BookingService.confirmCheckIn() yet,
  ///  - a review prompt for any confirmed, already-checked-out
  ///    booking that hasn't been reviewed yet,
  ///  - a one-time welcome/suggestion nudge for a guest who has never
  ///    booked and has no notifications yet.
  ///
  /// Safe to call on every screen open: existing notifications are
  /// fetched first and checked against before inserting anything, so
  /// the same checkpoint/prompt is never created twice. (The partial
  /// unique index in schema_notifications.sql is a server-side
  /// backstop for the same guarantee, not the primary mechanism -
  /// Postgres can't target a *partial* unique index from a plain
  /// `ON CONFLICT (columns)` upsert, so this checks first instead of
  /// relying on that.)
  static const _checkinMilestones = [3, 1, 0];

  Future<void> generateTimeBasedNotifications() async {
    final userId = _userId;
    if (userId == null) return;

    final bookings = await _bookingService.getUserBookings();
    final existing = await getNotifications();
    final existingReminderMilestones = {
      for (final n in existing)
        if (n.bookingId != null && n.type == 'checkin_reminder')
          '${n.bookingId}:${n.milestoneDays}',
    };
    final existingReviewPrompts = {
      for (final n in existing)
        if (n.bookingId != null && n.type == 'review_prompt') n.bookingId,
    };
    final existingCheckInLogReminders = {
      for (final n in existing)
        if (n.bookingId != null && n.type == 'checkin_log_reminder')
          n.bookingId,
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rows = <Map<String, dynamic>>[];

    for (final booking in bookings) {
      if (booking.status == 'cancelled') continue;

      final checkIn = DateTime(
          booking.checkIn.year, booking.checkIn.month, booking.checkIn.day);
      final checkOut = DateTime(booking.checkOut.year,
          booking.checkOut.month, booking.checkOut.day);
      final daysToCheckIn = checkIn.difference(today).inDays;

      // Walk checkpoints from furthest-out to closest and fire the
      // FIRST one that's been reached but not yet notified - e.g. a
      // guest who last opened the app 5 days out and opens again
      // 2 days out gets exactly one reminder (the 3-day checkpoint),
      // worded with the real "2 days to go", not a stale "3".
      if (daysToCheckIn >= 0) {
        for (final milestone in _checkinMilestones) {
          if (daysToCheckIn > milestone) continue;
          final key = '${booking.id}:$milestone';
          if (existingReminderMilestones.contains(key)) continue;

          rows.add(_row(
            userId: userId,
            type: 'checkin_reminder',
            title: daysToCheckIn == 0
                ? 'Check-in today!'
                : daysToCheckIn == 1
                    ? 'Check-in tomorrow'
                    : '$daysToCheckIn days to go',
            body: daysToCheckIn == 0
                ? 'You check in at ${booking.placeTitle} today. Have a great stay!'
                : 'Your stay at ${booking.placeTitle} is $daysToCheckIn '
                    '${daysToCheckIn == 1 ? 'day' : 'days'} away.',
            bookingId: booking.id,
            placeId: booking.placeId,
            milestoneDays: milestone,
          ));
          break;
        }
      }

      // Stay is live (today falls between check-in and checkout,
      // inclusive) and the guest hasn't tapped "I've checked in" yet -
      // one-shot nudge, same deduped-by-existence shape as
      // review_prompt below (not milestone-based, so milestoneDays
      // stays null - see schema_checked_in.sql).
      if (!today.isBefore(checkIn) &&
          !today.isAfter(checkOut) &&
          !booking.isCheckedIn &&
          !existingCheckInLogReminders.contains(booking.id)) {
        rows.add(_row(
          userId: userId,
          type: 'checkin_log_reminder',
          title: "Don't forget to log your check-in",
          body: 'Let your host know you\'ve arrived at '
              '${booking.placeTitle} - just a tap on your booking.',
          bookingId: booking.id,
          placeId: booking.placeId,
        ));
      }

      if (checkOut.isBefore(today) &&
          !existingReviewPrompts.contains(booking.id)) {
        final alreadyReviewed =
            await _reviewService.hasReviewedBooking(booking.id);
        if (!alreadyReviewed) {
          rows.add(_row(
            userId: userId,
            type: 'review_prompt',
            title: 'How was your stay?',
            body: 'Leave a review for your stay at ${booking.placeTitle} - '
                'it helps other guests and your host.',
            bookingId: booking.id,
            placeId: booking.placeId,
          ));
        }
      }
    }

    if (bookings.isEmpty && existing.isEmpty) {
      rows.add(_row(
        userId: userId,
        type: 'suggestion',
        title: 'Find your next stay',
        body: 'Explore homes and stays near you and book your first trip '
            'on Homely.',
      ));
    }

    if (rows.isEmpty) return;

    // A duplicate-key error here (23505) would only happen from a
    // genuine race - two calls to this method landing at almost the
    // same instant - which the existence check above already makes
    // vanishingly unlikely. Swallow it rather than surface an error
    // for what is, at worst, a missed reminder this one time.
    try {
      await _client.from('notifications').insert(rows);
    } catch (_) {
      // Best-effort - a failed lazy-generation pass just means the
      // reminder will be (re)tried the next time this runs.
    }
  }

  /// Fetches the single [Booking] a notification points to, so
  /// NotificationsScreen can push straight into BookingDetailScreen
  /// (which needs a full Booking, not just an id).
  Future<Booking?> getBookingById(String bookingId) async {
    final userId = _userId;
    if (userId == null) return null;

    final response = await _client
        .from('bookings')
        .select(
            '*, places(title, address, city_id, price_per_night, max_guests, host_id, host_public_info(full_name), cancellation_policy_type, cancellation_flexible_free_days, cancellation_flexible_fee_percent, cities(name), place_images(image_url, sort_order))')
        .eq('id', bookingId)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Booking.fromMap(response);
  }

  Map<String, dynamic> _row({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? bookingId,
    String? placeId,
    int? milestoneDays,
  }) {
    return {
      'user_id': userId,
      'type': type,
      'title': title,
      'body': body,
      'booking_id': bookingId,
      'place_id': placeId,
      'milestone_days': milestoneDays,
    };
  }
}
