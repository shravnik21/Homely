import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/services/host_listings_service.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/screens/host/host_profile_screen.dart';
import 'package:homely_app/screens/host/listing_wizard_screen.dart';
import 'package:homely_app/screens/host/my_listings_screen.dart';
import 'package:homely_app/screens/host/host_bookings_screen.dart';
import 'package:homely_app/utils/auto_reload_on_reconnect.dart';
import 'package:homely_app/utils/network_retry.dart';

/// Everything the Host Home dashboard needs, fetched together so the
/// stats row (listings + bookings counts) and the sections below it
/// always agree with each other and only ever show one loading spinner.
class _HostDashboardData {
  final List<Place> listings;
  final List<HostBooking> bookings;
  const _HostDashboardData({required this.listings, required this.bookings});
}

enum _BookingUpdateType { cancelled, rescheduled }

/// One recent change (cancellation or reschedule) a guest made to a
/// booking on one of the host's listings - built from [Booking]'s
/// cancelledAt/rescheduledAt fields, purely to drive the "Booking
/// updates" card below. Not persisted anywhere itself.
class _BookingUpdate {
  final _BookingUpdateType type;
  final String guestName;
  final String placeTitle;
  final DateTime when;
  final DateTime? previousCheckIn;
  final DateTime? previousCheckOut;
  final DateTime? newCheckIn;
  final DateTime? newCheckOut;

  const _BookingUpdate({
    required this.type,
    required this.guestName,
    required this.placeTitle,
    required this.when,
    this.previousCheckIn,
    this.previousCheckOut,
    this.newCheckIn,
    this.newCheckOut,
  });
}

/// Landing screen for hosts, shown instead of the guest [HomeScreen]
/// after logging in / signing up with the "Host" role selected.
class HostHomeScreen extends StatefulWidget {
  const HostHomeScreen({super.key});

  @override
  State<HostHomeScreen> createState() => _HostHomeScreenState();
}

class _HostHomeScreenState extends State<HostHomeScreen>
    with AutoReloadOnReconnectMixin {
  final AuthService _authService = AuthService();
  final HostListingsService _listingsService = HostListingsService();
  final HostBookingsService _bookingsService = HostBookingsService();

  late Future<_HostDashboardData> _dashboardFuture;

  String get _displayName {
    final meta = _authService.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return 'there';
    return name.trim().split(' ').first;
  }

  String get _initial {
    final meta = _authService.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return '?';
    return name.trim()[0].toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
    // Same reasoning as the guest HomeScreen: don't leave a host
    // stuck on a failed dashboard load just because they were
    // offline (or their clock hadn't finished syncing right after
    // reconnecting) - reload automatically once we're back online.
    startAutoReloadOnReconnect();
  }

  void _refreshDashboard() {
    setState(() {
      // Wrapped in withRetry so a transient clock-skew failure right
      // after reconnecting (PGRST303) resolves itself instead of
      // making the host manually pull-to-refresh.
      _dashboardFuture = withRetry(() => Future.wait([
            _listingsService.getMyListings(),
            _bookingsService.getBookingsForMyListings(),
          ]).then((results) => _HostDashboardData(
                listings: results[0] as List<Place>,
                bookings: results[1] as List<HostBooking>,
              )));
    });
  }

  @override
  void onReconnected() => _refreshDashboard();

  @override
  void dispose() {
    disposeAutoReloadOnReconnect();
    super.dispose();
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostProfileScreen()),
    );
  }

  Future<void> _addListing() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ListingWizardScreen()),
    );
    if (changed == true) _refreshDashboard();
  }

  Future<void> _manageListings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyListingsScreen()),
    );
    _refreshDashboard();
  }

  Future<void> _viewAllBookings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostBookingsScreen()),
    );
    // A cancel could have happened on that screen (guests can also
    // cancel from their side while the host is looking at this), so
    // refresh the dashboard counts/preview on return either way.
    _refreshDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: FutureBuilder<_HostDashboardData>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            final listings = snapshot.data?.listings ?? [];
            final bookings = snapshot.data?.bookings ?? [];
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            return RefreshIndicator(
              onRefresh: () async => _refreshDashboard(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildStatsRow(listings, bookings),
                  const SizedBox(height: 28),
                  _buildAddListingCard(),
                  const SizedBox(height: 16),
                  _buildBookingUpdatesCard(bookings),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Listings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.dark,
                        ),
                      ),
                      if (listings.isNotEmpty)
                        TextButton(
                          onPressed: _manageListings,
                          child: const Text('Manage all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (listings.isEmpty)
                    _buildEmptyListingsState()
                  else
                    ...listings
                        .take(3)
                        .map((p) => _buildListingRow(p))
                        ,
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Bookings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.dark,
                        ),
                      ),
                      if (bookings.isNotEmpty)
                        TextButton(
                          onPressed: _viewAllBookings,
                          child: const Text('View all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isLoading)
                    const SizedBox.shrink()
                  else if (bookings.isEmpty)
                    _buildEmptyBookingsState()
                  else
                    // Newest booking first, capped to a handful here -
                    // "View all" above opens the full list (with an
                    // Upcoming/Completed/Cancelled split) on
                    // HostBookingsScreen.
                    Column(
                      children: bookings
                          .take(5)
                          .map((b) => _buildBookingCard(b))
                          .toList(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBookingCard(HostBooking hostBooking) {
    final booking = hostBooking.booking;
    late final Color statusColor;
    late final String statusLabel;
    if (booking.status == 'cancelled') {
      statusColor = AppColors.error;
      statusLabel = 'Cancelled';
    } else if (booking.isUpcoming) {
      statusColor = Colors.green[700]!;
      statusLabel = 'Upcoming';
    } else {
      statusColor = AppColors.grey;
      statusLabel = 'Completed';
    }

    String formatDate(DateTime d) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${d.day} ${months[d.month - 1]}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: booking.coverImage,
                width: 58,
                height: 58,
                fit: BoxFit.cover,
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
                              fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
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
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 13, color: AppColors.grey),
                      const SizedBox(width: 4),
                      Text(
                        hostBooking.guestName,
                        style: const TextStyle(fontSize: 12, color: AppColors.grey),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.people_outline,
                          size: 13, color: AppColors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${booking.guests}',
                        style: const TextStyle(fontSize: 12, color: AppColors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatDate(booking.checkIn)} - ${formatDate(booking.checkOut)} '
                    '· ${booking.nights} night${booking.nights == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${booking.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingRow(Place place) {
    late final Color statusColor;
    late final String statusLabel;
    switch (place.status) {
      case 'draft':
        statusColor = AppColors.grey;
        statusLabel = 'Draft';
        break;
      case 'paused':
        statusColor = Colors.orange[700]!;
        statusLabel = 'Paused';
        break;
      default:
        statusColor = Colors.green[700]!;
        statusLabel = 'Active';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _manageListings,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: place.photoUrls.isEmpty
                    ? Container(
                        width: 52,
                        height: 52,
                        color: AppColors.white,
                        child: const Icon(Icons.image_not_supported_outlined,
                            size: 20, color: AppColors.grey),
                      )
                    : CachedNetworkImage(
                        imageUrl: place.coverImage,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  place.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back, host!',
              style: TextStyle(color: AppColors.primary, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              _displayName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: _openProfile,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(List<Place> listings, List<HostBooking> bookings) {
    final activeCount = listings.where((p) => p.isActive).length;
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(label: 'Listings', value: '$activeCount'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(label: 'Bookings', value: '${bookings.length}'),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(label: 'Earnings', value: '₹0')),
      ],
    );
  }

  Widget _buildStatCard({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAddListingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'List your place on Homely',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start earning by hosting guests at your farmhouse, villa or apartment.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 46),
            ),
            onPressed: _addListing,
            child: const Text('Add a Listing'),
          ),
        ],
      ),
    );
  }

  /// Cancellations and reschedules guests made in the last 14 days,
  /// across every listing this host owns - newest first. Built from
  /// data already fetched for the dashboard (no extra network call).
  List<_BookingUpdate> _recentBookingUpdates(List<HostBooking> bookings) {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final updates = <_BookingUpdate>[];
    for (final hb in bookings) {
      final b = hb.booking;
      final cancelledAt = b.cancelledAt;
      if (cancelledAt != null && cancelledAt.isAfter(cutoff)) {
        updates.add(_BookingUpdate(
          type: _BookingUpdateType.cancelled,
          guestName: hb.guestName,
          placeTitle: b.placeTitle,
          when: cancelledAt,
        ));
      }
      final rescheduledAt = b.rescheduledAt;
      if (rescheduledAt != null && rescheduledAt.isAfter(cutoff)) {
        updates.add(_BookingUpdate(
          type: _BookingUpdateType.rescheduled,
          guestName: hb.guestName,
          placeTitle: b.placeTitle,
          when: rescheduledAt,
          previousCheckIn: b.previousCheckIn,
          previousCheckOut: b.previousCheckOut,
          newCheckIn: b.checkIn,
          newCheckOut: b.checkOut,
        ));
      }
    }
    updates.sort((a, b) => b.when.compareTo(a.when));
    return updates;
  }

  String _fmtShort(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _describeUpdate(_BookingUpdate update) {
    switch (update.type) {
      case _BookingUpdateType.cancelled:
        return '${update.guestName} cancelled their stay at '
            '${update.placeTitle}.';
      case _BookingUpdateType.rescheduled:
        final newIn = update.newCheckIn;
        final newOut = update.newCheckOut;
        final newDates = (newIn != null && newOut != null)
            ? ' New dates: ${_fmtShort(newIn)} - ${_fmtShort(newOut)}.'
            : '';
        return '${update.guestName} rescheduled their stay at '
            '${update.placeTitle}.$newDates';
    }
  }

  /// Same visual style as [_buildAddListingCard] ("List your place on
  /// Homely") so the two read as a pair, but dark instead of primary
  /// so the two don't get confused for the same action. Tapping it,
  /// like "Manage all" / "View all" elsewhere on this screen, opens
  /// [HostBookingsScreen] - guests can cancel or reschedule from
  /// their own MyBookingsScreen at any time, so this is where a host
  /// goes to see the full picture and act on it.
  Widget _buildBookingUpdatesCard(List<HostBooking> bookings) {
    final updates = _recentBookingUpdates(bookings);
    final hasUpdates = updates.isNotEmpty;
    return GestureDetector(
      onTap: _viewAllBookings,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_toggle_off_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Booking updates',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (hasUpdates)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${updates.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hasUpdates
                  ? 'Guests have cancelled or rescheduled on your listings '
                      'in the last 14 days.'
                  : "You'll see it here when a guest cancels or reschedules "
                      'a booking on one of your listings.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (hasUpdates) ...[
              const SizedBox(height: 14),
              ...updates.take(2).map(
                    (u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            u.type == _BookingUpdateType.cancelled
                                ? Icons.cancel_outlined
                                : Icons.event_repeat_rounded,
                            color: Colors.white70,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _describeUpdate(u),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (updates.length > 2)
                Text(
                  '+${updates.length - 2} more',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  hasUpdates ? 'View all bookings' : 'Go to your bookings',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyListingsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Text(
        "You haven't added any listings yet.",
        style: TextStyle(color: AppColors.grey, fontSize: 13),
      ),
    );
  }

  Widget _buildEmptyBookingsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Text(
        'No bookings yet. They will show up here once guests book your place.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.grey, fontSize: 13),
      ),
    );
  }
}
