import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/screens/host/host_booking_detail_screen.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/utils/network_retry.dart';

/// Month-view calendar for the host, showing every booking across
/// ALL of their listings at once (as opposed to the guest-side
/// availability calendar in availability_date_range_sheet.dart, which
/// is scoped to one listing and only greys out dates - this one is
/// scoped to one host and actively surfaces who's arriving when).
///
/// Tapping a date that has one or more bookings pops open a small
/// floating card anchored near where the host tapped, listing each
/// booking on that date (listing + guest + date range); tapping a row
/// in that card opens the full [HostBookingDetailScreen].
class HostCalendarScreen extends StatefulWidget {
  const HostCalendarScreen({super.key});

  @override
  State<HostCalendarScreen> createState() => _HostCalendarScreenState();
}

class _HostCalendarScreenState extends State<HostCalendarScreen> {
  final HostBookingsService _bookingsService = HostBookingsService();

  late Future<List<HostBooking>> _bookingsFuture;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // Kept in the coordinate space of _stackKey's own box (not raw
  // screen/global coordinates) since that's what the floating card
  // below is Positioned relative to.
  Offset? _tapPosition;
  final GlobalKey _stackKey = GlobalKey();

  // Map from a day (date-only) to every booking that covers that
  // night (check-in inclusive, check-out exclusive - same convention
  // AvailabilityService/the guest calendar use elsewhere in the app).
  Map<DateTime, List<HostBooking>> _bookingsByDate = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _bookingsFuture = withRetry(() => _bookingsService.getBookingsForMyListings())
          .then((bookings) {
        _bookingsByDate = _groupByDate(bookings);
        return bookings;
      });
    });
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<DateTime, List<HostBooking>> _groupByDate(List<HostBooking> bookings) {
    final map = <DateTime, List<HostBooking>>{};
    for (final hb in bookings) {
      if (hb.booking.status == 'cancelled') continue;
      for (var d = _dateOnly(hb.booking.checkIn);
          d.isBefore(_dateOnly(hb.booking.checkOut));
          d = d.add(const Duration(days: 1))) {
        map.putIfAbsent(d, () => []).add(hb);
      }
    }
    return map;
  }

  List<HostBooking> _bookingsFor(DateTime day) =>
      _bookingsByDate[_dateOnly(day)] ?? const [];

  /// Converts a raw pointer position (global/screen coordinates) into
  /// this screen's own [_stackKey] box's local coordinate space, so it
  /// lines up with the [Positioned] floating card below - which lives
  /// inside that Stack, offset from the screen's top-left by the
  /// AppBar/status bar.
  Offset? _toLocal(Offset globalPosition) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.globalToLocal(globalPosition);
  }

  void _onDayTapped(DateTime day, Offset globalTapPosition) {
    final bookings = _bookingsFor(day);
    final local = _toLocal(globalTapPosition) ?? globalTapPosition;
    if (bookings.isEmpty) {
      // Tapping an empty date just clears any open card, same as
      // tapping the dimmed backdrop would.
      setState(() {
        _selectedDay = null;
        _tapPosition = null;
      });
      return;
    }
    setState(() {
      _focusedDay = day;
      _selectedDay = _dateOnly(day);
      _tapPosition = local;
    });
  }

  void _dismissCard() {
    setState(() {
      _selectedDay = null;
      _tapPosition = null;
    });
  }

  void _openBookingDetail(HostBooking hostBooking) {
    _dismissCard();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostBookingDetailScreen(hostBooking: hostBooking),
      ),
    );
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
          'Booking Calendar',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.dark),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<HostBooking>>(
          future: _bookingsFuture,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final failed = snapshot.hasError;

            if (loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (failed) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        friendlyError(
                          snapshot.error!,
                          fallback: 'Could not load your bookings.',
                        ),
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

            final allBookings = snapshot.data ?? [];
            final activeCount =
                allBookings.where((b) => b.booking.status != 'cancelled').length;

            return LayoutBuilder(
              builder: (context, constraints) {
                final localSize = constraints.biggest;
                return Stack(
                  key: _stackKey,
                  children: [
                    RefreshIndicator(
                      onRefresh: () async => _load(),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _buildLegend(activeCount),
                          const SizedBox(height: 8),
                          _buildCalendar(),
                          if (activeCount == 0) ...[
                            const SizedBox(height: 24),
                            _buildEmptyState(),
                          ],
                        ],
                      ),
                    ),
                    // Transparent tap-catcher behind the floating card
                    // so tapping anywhere outside it dismisses it.
                    if (_selectedDay != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _dismissCard,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    if (_selectedDay != null && _tapPosition != null)
                      _buildFloatingCard(localSize),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegend(int activeCount) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'Dates with a booking - tap a date to see details',
          style: TextStyle(fontSize: 12.5, color: AppColors.grey),
        ),
        const Spacer(),
        if (activeCount > 0)
          Text(
            '$activeCount total',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildCalendar() {
    return TableCalendar<HostBooking>(
      firstDay: DateTime.now().subtract(const Duration(days: 365)),
      lastDay: DateTime.now().add(const Duration(days: 365)),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) =>
          _selectedDay != null && isSameDay(day, _selectedDay),
      calendarFormat: CalendarFormat.month,
      availableGestures: AvailableGestures.horizontalSwipe,
      eventLoader: _bookingsFor,
      onPageChanged: (focused) => setState(() => _focusedDay = focused),
      // onDaySelected still gives us the logical day; the Listener
      // wrapped around each cell in calendarBuilders below gives us
      // the raw tap position for anchoring the floating card, since
      // TableCalendar itself doesn't expose tap coordinates.
      onDaySelected: (selected, focused) {
        _focusedDay = focused;
        if (_tapPosition != null) _onDayTapped(selected, _tapPosition!);
      },
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      calendarStyle: const CalendarStyle(
        outsideDaysVisible: false,
        markersMaxCount: 1,
        markerDecoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        todayDecoration: BoxDecoration(
          color: AppColors.lightGrey,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(color: AppColors.dark),
        selectedDecoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) {
          final hasBooking = _bookingsFor(day).isNotEmpty;
          return Listener(
            onPointerDown: (event) => _tapPosition = event.position,
            child: Container(
              margin: const EdgeInsets.all(4),
              alignment: Alignment.center,
              decoration: hasBooking
                  ? BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: hasBooking ? AppColors.primary : AppColors.dark,
                  fontWeight: hasBooking ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
        selectedBuilder: (context, day, focusedDay) {
          return Listener(
            onPointerDown: (event) => _tapPosition = event.position,
            child: Container(
              margin: const EdgeInsets.all(4),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          );
        },
        todayBuilder: (context, day, focusedDay) {
          final hasBooking = _bookingsFor(day).isNotEmpty;
          return Listener(
            onPointerDown: (event) => _tapPosition = event.position,
            child: Container(
              margin: const EdgeInsets.all(4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasBooking
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.lightGrey,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 1.2),
              ),
              child: Text(
                '${day.day}',
                style: const TextStyle(
                    color: AppColors.dark, fontWeight: FontWeight.w700),
              ),
            ),
          );
        },
        // Hide the default dot marker under the day number - the
        // tinted circle background above is enough of a signal, and
        // avoids double-marking the same date.
        markerBuilder: (context, day, events) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Text(
        'No bookings yet. Once guests book any of your listings, '
        'those dates will show up here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.grey, fontSize: 13),
      ),
    );
  }

  /// Positions the floating details card near [_tapPosition], flipping
  /// it above the tapped date instead of below when there isn't
  /// enough room at the bottom of the screen, and clamping it
  /// horizontally so it never runs off either edge.
  Widget _buildFloatingCard(Size stackSize) {
    // Adaptive so this never overflows on a narrow phone (or looks
    // silly stretched full-width on a tablet).
    final cardWidth = (stackSize.width - 24.0).clamp(220.0, 300.0);
    const maxCardHeight = 320.0;
    final tap = _tapPosition!;

    double left = tap.dx - cardWidth / 2;
    final maxLeft = stackSize.width - cardWidth - 12.0;
    left = left.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    final showAbove = tap.dy > stackSize.height * 0.55;
    final top = showAbove ? null : tap.dy + 18;
    final bottom = showAbove ? (stackSize.height - tap.dy) + 18 : null;

    final bookings = _bookingsFor(_selectedDay!);

    return Positioned(
      left: left,
      top: top,
      bottom: bottom,
      width: cardWidth,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          alignment: showAbove ? Alignment.bottomCenter : Alignment.topCenter,
          child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
        ),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(16),
          shadowColor: Colors.black.withValues(alpha: 0.3),
          child: Container(
            constraints: const BoxConstraints(maxHeight: maxCardHeight),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatCardTitle(_selectedDay!),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.dark,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _dismissCard,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 18, color: AppColors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: bookings.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _buildBookingRow(bookings[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingRow(HostBooking hostBooking) {
    final booking = hostBooking.booking;
    return InkWell(
      onTap: () => _openBookingDetail(hostBooking),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: booking.coverImage,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.placeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 8,
                        backgroundColor: AppColors.primary,
                        backgroundImage: hostBooking.guestAvatarUrl != null
                            ? CachedNetworkImageProvider(
                                hostBooking.guestAvatarUrl!)
                            : null,
                        child: hostBooking.guestAvatarUrl == null
                            ? Text(
                                hostBooking.guestInitial,
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hostBooking.guestName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatShortDate(booking.checkIn)} - '
                    '${_formatShortDate(booking.checkOut)} '
                    '(${booking.guests} guest${booking.guests == 1 ? '' : 's'})',
                    style: const TextStyle(fontSize: 11, color: AppColors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.grey),
          ],
        ),
      ),
    );
  }

  String _formatCardTitle(DateTime day) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final bookings = _bookingsFor(day);
    final countLabel =
        '${bookings.length} booking${bookings.length == 1 ? '' : 's'}';
    return '${day.day} ${months[day.month - 1]} ${day.year} - $countLabel';
  }

  String _formatShortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
