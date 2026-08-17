import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/screens/host/host_booking_detail_screen.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/widgets/error_state_view.dart';

/// Full list of bookings across every listing the host owns, opened
/// from the "View all" link on [HostHomeScreen]'s Recent Bookings
/// section. Unlike that dashboard preview (which only shows a
/// handful), this screen holds every booking, split into tabs so a
/// cancelled booking isn't just mixed in with everything else - it
/// has its own place to look. Tapping any card opens the full
/// [HostBookingDetailScreen] for that booking.
class HostBookingsScreen extends StatefulWidget {
  const HostBookingsScreen({super.key});

  @override
  State<HostBookingsScreen> createState() => _HostBookingsScreenState();
}

class _HostBookingsScreenState extends State<HostBookingsScreen> {
  final HostBookingsService _bookingsService = HostBookingsService();
  late Future<List<HostBooking>> _bookingsFuture;

  // Same local-tracking trick as MyBookingsScreen (guest side): the
  // hide has already succeeded server-side by the time an id lands
  // here, this just avoids a full-list reload/flash right after the
  // swipe animation.
  final Set<String> _hiddenIds = {};

  @override
  void initState() {
    super.initState();
    _bookingsFuture = _bookingsService.getBookingsForMyListings();
  }

  void _refresh() {
    setState(() {
      _bookingsFuture = _bookingsService.getBookingsForMyListings();
    });
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _openDetail(HostBooking hostBooking) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostBookingDetailScreen(hostBooking: hostBooking),
      ),
    );
    // A note or (from the guest's side) a cancellation could have
    // happened while that screen was open - refresh so the list and
    // tab counts stay accurate.
    _refresh();
  }

  /// Gate + confirm + actually perform a swipe-delete. Returns true
  /// only once the hide has genuinely succeeded server-side, since
  /// that's what tells [Dismissible] it's safe to finish removing the
  /// card - if this returns false, the card slides back into place.
  /// Restricted to bookings that are no longer active (past checkout,
  /// or cancelled) - a host shouldn't be able to swipe away a guest
  /// who's currently booked in or arriving soon.
  Future<bool> _confirmDelete(HostBooking hostBooking) async {
    final booking = hostBooking.booking;
    if (booking.isUpcoming) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You can only remove past or cancelled bookings."),
        ),
      );
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this booking?'),
        content: const Text(
          "This only removes it from your bookings list - it won't notify "
          "the guest or change their booking.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await _bookingsService.hideBooking(booking.id);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: "Couldn't remove that booking."))),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          centerTitle: true,
          foregroundColor: AppColors.dark,
          title: const Text(
            'Your Bookings',
            style: TextStyle(
              color: AppColors.dark,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.grey,
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<HostBooking>>(
            future: _bookingsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ErrorStateView(
                  error: snapshot.error!,
                  fallbackMessage: 'Could not load bookings.',
                  onRetry: _refresh,
                );
              }

              final all = (snapshot.data ?? [])
                  .where((b) => !_hiddenIds.contains(b.booking.id))
                  .toList();
              // Cancelled takes priority in the split so a booking
              // that was cancelled after the fact never lingers in
              // Upcoming/Completed - a cancelled booking is always
              // "Cancelled" regardless of its dates.
              final cancelled =
                  all.where((b) => b.booking.status == 'cancelled').toList();
              final upcoming = all
                  .where((b) =>
                      b.booking.status != 'cancelled' && b.booking.isUpcoming)
                  .toList();
              final completed = all
                  .where((b) =>
                      b.booking.status != 'cancelled' && !b.booking.isUpcoming)
                  .toList();

              return TabBarView(
                children: [
                  _buildList(upcoming,
                      emptyText: 'No upcoming bookings right now.'),
                  _buildList(completed,
                      emptyText: 'No completed stays yet.'),
                  _buildList(cancelled,
                      emptyText: 'No cancelled bookings.'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<HostBooking> bookings, {required String emptyText}) {
    if (bookings.isEmpty) {
      return ListView(
        // Wrapped in a scrollable so pull-to-refresh still works even
        // when the tab is empty.
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey, fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final hostBooking = bookings[index];
        return Dismissible(
          key: ValueKey(hostBooking.booking.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(hostBooking),
          onDismissed: (_) =>
              setState(() => _hiddenIds.add(hostBooking.booking.id)),
          background: _buildDeleteBackground(),
          child: _HostBookingCard(
            hostBooking: hostBooking,
            formatDate: _fmt,
            onTap: () => _openDetail(hostBooking),
          ),
        );
      },
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerRight,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          SizedBox(height: 2),
          Text('Delete',
              style: TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HostBookingCard extends StatelessWidget {
  final HostBooking hostBooking;
  final String Function(DateTime) formatDate;
  final VoidCallback onTap;

  const _HostBookingCard({
    required this.hostBooking,
    required this.formatDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final booking = hostBooking.booking;
    final cancelled = booking.status == 'cancelled';
    final currentlyHosting = !cancelled &&
        !booking.checkIn.isAfter(DateTime.now()) &&
        booking.checkOut.isAfter(DateTime.now());
    final statusLabel = cancelled
        ? 'Cancelled'
        : (currentlyHosting
            ? 'Currently hosting'
            : (booking.isUpcoming ? 'Upcoming' : 'Completed'));
    final statusColor = cancelled
        ? AppColors.error
        : (booking.isUpcoming ? Colors.green[700]! : AppColors.grey);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: booking.coverImage,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 64,
                  height: 64,
                  color: AppColors.lightGrey,
                ),
                errorWidget: (context, url, error) => Container(
                  width: 64,
                  height: 64,
                  color: AppColors.lightGrey,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: AppColors.grey, size: 20),
                ),
              ),
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
                          booking.placeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _GuestAvatar(hostBooking: hostBooking),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hostBooking.guestName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.dark,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.people_outline,
                          size: 13, color: AppColors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${booking.guests}',
                        style: const TextStyle(color: AppColors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 13, color: AppColors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${formatDate(booking.checkIn)} - ${formatDate(booking.checkOut)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.dark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${booking.nights} night${booking.nights == 1 ? '' : 's'} · ₹${booking.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Small round guest avatar used on each booking row - a photo if the
/// guest has one, otherwise a colored initial (same pattern as the
/// host's own avatar bubble on Host Home).
class _GuestAvatar extends StatelessWidget {
  final HostBooking hostBooking;

  const _GuestAvatar({required this.hostBooking});

  @override
  Widget build(BuildContext context) {
    final url = hostBooking.guestAvatarUrl;
    const size = 18.0;
    if (url != null && url.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => _initialCircle(),
        ),
      );
    }
    return _initialCircle();
  }

  Widget _initialCircle() {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
      alignment: Alignment.center,
      child: Text(
        hostBooking.guestInitial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
