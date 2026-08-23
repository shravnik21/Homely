import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/app_notification.dart';
import 'package:homely_app/screens/chat_screen.dart';
import 'package:homely_app/screens/host/host_booking_detail_screen.dart';
import 'package:homely_app/screens/host/host_reviews_screen.dart';
import 'package:homely_app/services/host_notifications_service.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/utils/network_retry.dart';

/// Host-facing feed of listing/booking updates - new bookings,
/// cancellations, reschedules, guest messages, new reviews, and
/// smart-lock PIN reminders. Same card-list UI as the guest
/// NotificationsScreen, kept as a separate screen (rather than one
/// screen branching on role) since the navigation each row leads to
/// is genuinely different on this side - HostBookingDetailScreen,
/// HostReviewsScreen, etc. See HostNotificationsService and
/// schema_host_notifications.sql for how each type is created.
class HostNotificationsScreen extends StatefulWidget {
  const HostNotificationsScreen({super.key});

  @override
  State<HostNotificationsScreen> createState() => _HostNotificationsScreenState();
}

class _HostNotificationsScreenState extends State<HostNotificationsScreen> {
  final HostNotificationsService _service = HostNotificationsService();
  late Future<List<AppNotification>> _future;

  // Tracks per-row "opening..." state so a slow tap can't fire twice
  // while its booking is being fetched.
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = withRetry(() async {
        // Generate any newly-due PIN reminders first, so this always
        // shows an up-to-date feed rather than whatever was there
        // the last time the host happened to open it.
        await _service.generateTimeBasedNotifications();
        return _service.getNotifications();
      });
    });
  }

  Future<void> _markAllRead(List<AppNotification> current) async {
    if (current.every((n) => n.isRead)) return;
    await _service.markAllAsRead();
    _load();
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead) {
      // Optimistic - flips locally right away, backend call happens
      // in the background so the tap feels instant.
      _service.markAsRead(notification.id);
    }

    // A new-review notification isn't tied to any one booking a host
    // needs to manage - send them to the Reviews hub instead of
    // trying to resolve a booking.
    if (notification.type == 'new_review') {
      setState(() {});
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HostReviewsScreen()),
      );
      if (mounted) _load();
      return;
    }

    if (notification.bookingId == null) {
      setState(() {}); // repaint the read/unread dot without a refetch
      return;
    }

    setState(() => _openingId = notification.id);
    try {
      final hostBooking = await _service.getHostBookingById(notification.bookingId!);
      if (!mounted) return;
      if (hostBooking == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That booking isn't available anymore.")),
        );
        return;
      }

      if (notification.type == 'new_message') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              bookingId: hostBooking.booking.id,
              otherPartyId: hostBooking.booking.userId,
              otherPartyName: hostBooking.guestName,
              otherPartyIsHost: false,
              placeTitle: hostBooking.booking.placeTitle,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HostBookingDetailScreen(hostBooking: hostBooking)),
        );
      }
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: "Couldn't open that booking."))),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.dark),
        ),
        actions: [
          FutureBuilder<List<AppNotification>>(
            future: _future,
            builder: (context, snapshot) {
              final list = snapshot.data ?? const [];
              final hasUnread = list.any((n) => !n.isRead);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _markAllRead(list),
                child: const Text('Mark all read',
                    style: TextStyle(fontSize: 13, color: AppColors.primary)),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        friendlyError(snapshot.error!,
                            fallback: 'Could not load your notifications.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              );
            }

            final notifications = snapshot.data ?? [];
            if (notifications.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: notifications.length,
                itemBuilder: (context, i) => _buildCard(notifications[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard(AppNotification n) {
    final isOpening = _openingId == n.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: n.isRead
            ? AppColors.white
            : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: n.isRead
              ? AppColors.lightGrey
              : AppColors.primary.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isOpening ? null : () => _openNotification(n),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: n.iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(n.icon, size: 21, color: n.iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: n.isRead
                                    ? FontWeight.w600
                                    : FontWeight.bold,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 6, top: 3),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n.body,
                        style: const TextStyle(fontSize: 13, color: AppColors.grey, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _timeAgo(n.createdAt),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (isOpening)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (n.bookingId != null || n.type == 'new_review')
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 20, color: AppColors.grey),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.notifications_none_rounded,
                  size: 34, color: AppColors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              "You're all caught up",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'New bookings, cancellations, messages, and reviews on your '
              'listings will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}
