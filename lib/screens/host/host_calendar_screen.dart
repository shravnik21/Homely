import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/models/blocked_date.dart';
import 'package:homely_app/services/host_listings_service.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/services/blocked_dates_service.dart';
import 'package:homely_app/screens/host/host_booking_detail_screen.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/utils/network_retry.dart';

/// Everything the host calendar needs, fetched together so bookings,
/// blocked dates, and the listing-filter chips never disagree with
/// each other and only ever show one loading spinner.
class _HostCalendarData {
  final List<Place> listings;
  final List<HostBooking> bookings;
  final List<BlockedDate> blockedDates;
  const _HostCalendarData({
    required this.listings,
    required this.bookings,
    required this.blockedDates,
  });
}

/// Month-view calendar for the host, showing every booking across ALL
/// of their listings at once (as opposed to the guest-side
/// availability calendar in availability_date_range_sheet.dart, which
/// is scoped to one listing and only greys out dates - this one is
/// scoped to one host and actively surfaces who's arriving when).
///
/// Also where a host blocks/unblocks dates on a specific listing
/// (personal use, maintenance, etc) - a blocked date is folded into
/// AvailabilityService on the guest side automatically, so it shows
/// up greyed-out there with no further wiring needed.
///
/// Tapping a date that has a booking or a blocked date pops open a
/// small floating card anchored near where the host tapped; tapping a
/// booking row in that card opens the full [HostBookingDetailScreen],
/// and a blocked-date row can be un-blocked right from the card.
class HostCalendarScreen extends StatefulWidget {
  const HostCalendarScreen({super.key});

  @override
  State<HostCalendarScreen> createState() => _HostCalendarScreenState();
}

class _HostCalendarScreenState extends State<HostCalendarScreen> {
  final HostListingsService _listingsService = HostListingsService();
  final HostBookingsService _bookingsService = HostBookingsService();
  final BlockedDatesService _blockedDatesService = BlockedDatesService();

  late Future<_HostCalendarData> _dataFuture;
  List<Place> _listings = [];
  List<HostBooking> _allBookings = [];
  List<BlockedDate> _allBlocked = [];

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // Coordinate space of _stackKey's own box (not raw screen/global
  // coordinates), so it lines up with the Positioned floating card
  // below, which lives inside that same Stack.
  Offset? _tapPosition;
  final GlobalKey _stackKey = GlobalKey();

  // null = "All listings". Blocking requires one specific listing to
  // be selected, since a blocked date always belongs to exactly one
  // listing.
  String? _selectedListingId;
  bool _blockMode = false;
  bool _savingBlock = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _dataFuture = withRetry(() => Future.wait([
            _listingsService.getMyListings(),
            _bookingsService.getBookingsForMyListings(),
            _blockedDatesService.getBlockedDatesForMyListings(),
          ])).then((results) {
        _listings = results[0] as List<Place>;
        _allBookings = results[1] as List<HostBooking>;
        _allBlocked = results[2] as List<BlockedDate>;
        return _HostCalendarData(
          listings: _listings,
          bookings: _allBookings,
          blockedDates: _allBlocked,
        );
      });
    });
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Bookings visible on the calendar right now - all of them, unless
  /// a specific listing is selected, in which case only that
  /// listing's.
  List<HostBooking> get _visibleBookings => _selectedListingId == null
      ? _allBookings
      : _allBookings
          .where((b) => b.booking.placeId == _selectedListingId)
          .toList();

  List<BlockedDate> get _visibleBlocked => _selectedListingId == null
      ? _allBlocked
      : _allBlocked.where((b) => b.placeId == _selectedListingId).toList();

  List<HostBooking> _bookingsFor(DateTime day) {
    final d = _dateOnly(day);
    return _visibleBookings.where((hb) {
      if (hb.booking.status == 'cancelled') return false;
      final checkIn = _dateOnly(hb.booking.checkIn);
      final checkOut = _dateOnly(hb.booking.checkOut);
      return !d.isBefore(checkIn) && d.isBefore(checkOut);
    }).toList();
  }

  List<BlockedDate> _blockedFor(DateTime day) {
    final d = _dateOnly(day);
    return _visibleBlocked.where((b) => isSameDay(b.date, d)).toList();
  }

  String? get _selectedListingTitle {
    if (_selectedListingId == null) return null;
    for (final p in _listings) {
      if (p.id == _selectedListingId) return p.title;
    }
    return null;
  }

  /// Converts a raw pointer position (global/screen coordinates) into
  /// this screen's own [_stackKey] box's local coordinate space, so it
  /// lines up with the [Positioned] floating card below.
  Offset? _toLocal(Offset globalPosition) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.globalToLocal(globalPosition);
  }

  void _selectListing(String? placeId) {
    setState(() {
      _selectedListingId = placeId;
      if (placeId == null) _blockMode = false;
      _selectedDay = null;
      _tapPosition = null;
    });
  }

  void _onDayTapped(DateTime day, Offset globalTapPosition) {
    final dayOnly = _dateOnly(day);

    if (_blockMode && _selectedListingId != null) {
      _toggleBlock(dayOnly);
      return;
    }

    final bookings = _bookingsFor(dayOnly);
    final blocked = _blockedFor(dayOnly);
    final local = _toLocal(globalTapPosition) ?? globalTapPosition;

    if (bookings.isEmpty && blocked.isEmpty) {
      setState(() {
        _selectedDay = null;
        _tapPosition = null;
      });
      return;
    }

    setState(() {
      _focusedDay = day;
      _selectedDay = dayOnly;
      _tapPosition = local;
    });
  }

  void _dismissCard() {
    setState(() {
      _selectedDay = null;
      _tapPosition = null;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleBlock(DateTime day) async {
    final listingId = _selectedListingId;
    final listingTitle = _selectedListingTitle;
    if (listingId == null || listingTitle == null) return;

    if (day.isBefore(_dateOnly(DateTime.now()))) {
      _showSnack("You can't block a date in the past.");
      return;
    }
    final hasBooking = _bookingsFor(day)
        .any((b) => b.booking.placeId == listingId);
    if (hasBooking) {
      _showSnack("That date is already booked - it can't be blocked.");
      return;
    }
    if (_savingBlock) return;

    final alreadyBlocked =
        _blockedFor(day).any((b) => b.placeId == listingId);

    setState(() => _savingBlock = true);
    try {
      if (alreadyBlocked) {
        await _blockedDatesService.unblockDate(placeId: listingId, date: day);
        setState(() {
          _allBlocked.removeWhere(
              (b) => b.placeId == listingId && isSameDay(b.date, day));
        });
        _showSnack('Unblocked ${_formatShortDate(day)} for $listingTitle');
      } else {
        await _blockedDatesService.blockDate(placeId: listingId, date: day);
        setState(() {
          _allBlocked.add(BlockedDate(
            placeId: listingId,
            placeTitle: listingTitle,
            date: day,
          ));
        });
        _showSnack('Blocked ${_formatShortDate(day)} for $listingTitle');
      }
    } catch (e) {
      _showSnack(friendlyError(e, fallback: "Couldn't update that date - try again."));
    } finally {
      if (mounted) setState(() => _savingBlock = false);
    }
  }

  Future<void> _unblockFromCard(BlockedDate blockedDate) async {
    setState(() => _savingBlock = true);
    try {
      await _blockedDatesService.unblockDate(
        placeId: blockedDate.placeId,
        date: blockedDate.date,
      );
      setState(() {
        _allBlocked.removeWhere((b) =>
            b.placeId == blockedDate.placeId &&
            isSameDay(b.date, blockedDate.date));
      });
      _dismissCard();
      _showSnack(
          'Unblocked ${_formatShortDate(blockedDate.date)} for ${blockedDate.placeTitle}');
    } catch (e) {
      _showSnack(friendlyError(e, fallback: "Couldn't update that date - try again."));
    } finally {
      if (mounted) setState(() => _savingBlock = false);
    }
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
        child: FutureBuilder<_HostCalendarData>(
          future: _dataFuture,
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
                          fallback: 'Could not load your calendar.',
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

            final activeCount =
                _allBookings.where((b) => b.booking.status != 'cancelled').length;

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
                          if (_listings.length > 1) ...[
                            _buildListingSelector(),
                            const SizedBox(height: 14),
                          ],
                          _buildBlockControls(),
                          const SizedBox(height: 12),
                          _buildLegend(activeCount),
                          const SizedBox(height: 8),
                          _buildCalendar(),
                          if (activeCount == 0 && _allBlocked.isEmpty) ...[
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

  /// Horizontal chip row to scope the calendar (and blocking) to one
  /// listing, or back to "All listings". Only shown when the host has
  /// more than one listing - with just one, there's nothing to
  /// disambiguate.
  Widget _buildListingSelector() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildListingChip(
            label: 'All listings',
            selected: _selectedListingId == null,
            onTap: () => _selectListing(null),
          ),
          const SizedBox(width: 8),
          for (final place in _listings) ...[
            _buildListingChip(
              label: place.title,
              selected: _selectedListingId == place.id,
              onTap: () => _selectListing(place.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildListingChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.dark,
          ),
        ),
      ),
    );
  }

  /// The block/unblock toggle - only usable once a specific listing
  /// is selected, since a blocked date always belongs to one listing.
  Widget _buildBlockControls() {
    if (_selectedListingId == null) {
      if (_listings.length <= 1 && _listings.isNotEmpty) {
        // Single-listing hosts don't need the chip row above, but
        // still need a listing selected to block dates - do it for
        // them silently.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedListingId == null) {
            setState(() => _selectedListingId = _listings.first.id);
          }
        });
        return const SizedBox.shrink();
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.grey),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Select a listing above to block dates for it.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _blockMode ? AppColors.dark : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _blockMode ? Icons.block_rounded : Icons.event_busy_rounded,
            size: 18,
            color: _blockMode ? Colors.white : AppColors.dark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _blockMode
                  ? 'Tap a free date to block it, tap a blocked date to '
                      'unblock it.'
                  : "Block dates so guests can't book them on "
                      '${_selectedListingTitle ?? "this listing"}.',
              style: TextStyle(
                fontSize: 12.5,
                color: _blockMode ? Colors.white70 : AppColors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: _blockMode,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() {
              _blockMode = v;
              _selectedDay = null;
              _tapPosition = null;
            }),
          ),
        ],
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
        const Text('Booked', style: TextStyle(fontSize: 12, color: AppColors.grey)),
        const SizedBox(width: 14),
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: AppColors.grey.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text('Blocked', style: TextStyle(fontSize: 12, color: AppColors.grey)),
        const Spacer(),
        if (activeCount > 0)
          Text(
            '$activeCount booking${activeCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildCalendar() {
    return TableCalendar<Object>(
      firstDay: DateTime.now().subtract(const Duration(days: 365)),
      lastDay: DateTime.now().add(const Duration(days: 365)),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) =>
          _selectedDay != null && isSameDay(day, _selectedDay),
      calendarFormat: CalendarFormat.month,
      availableGestures: AvailableGestures.horizontalSwipe,
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
      calendarStyle: const CalendarStyle(outsideDaysVisible: false),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) =>
            _dayCell(day, isToday: false),
        todayBuilder: (context, day, focusedDay) =>
            _dayCell(day, isToday: true),
        selectedBuilder: (context, day, focusedDay) => Listener(
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
        ),
      ),
    );
  }

  /// One calendar cell. Booked takes visual priority over blocked
  /// when a date is somehow both (only possible in "All listings"
  /// view, where a booking on one listing and a block on a different
  /// listing can share the same date) - the floating card underneath
  /// still lists both accurately regardless of which color wins here.
  Widget _dayCell(DateTime day, {required bool isToday}) {
    final hasBooking = _bookingsFor(day).isNotEmpty;
    final hasBlocked = !hasBooking && _blockedFor(day).isNotEmpty;

    Color? fill;
    Color textColor = AppColors.dark;
    FontWeight weight = FontWeight.normal;
    Widget? badge;

    if (hasBooking) {
      fill = AppColors.primary.withValues(alpha: isToday ? 0.22 : 0.10);
      textColor = AppColors.primary;
      weight = FontWeight.w700;
    } else if (hasBlocked) {
      fill = AppColors.grey.withValues(alpha: isToday ? 0.28 : 0.16);
      textColor = AppColors.dark;
      weight = FontWeight.w700;
      badge = Positioned(
        bottom: 2,
        right: 2,
        child: Icon(Icons.block_rounded, size: 9, color: AppColors.grey.withValues(alpha: 0.9)),
      );
    }

    return Listener(
      onPointerDown: (event) => _tapPosition = event.position,
      child: Container(
        margin: const EdgeInsets.all(4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: isToday ? Border.all(color: AppColors.primary, width: 1.2) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text('${day.day}', style: TextStyle(color: textColor, fontWeight: weight)),
            if (badge != null) badge,
          ],
        ),
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
        'No bookings or blocked dates yet. Once guests book, or you '
        'block a date, it will show up here.',
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
    final cardWidth = (stackSize.width - 24.0).clamp(220.0, 300.0);
    const maxCardHeight = 340.0;
    final tap = _tapPosition!;

    double left = tap.dx - cardWidth / 2;
    final maxLeft = stackSize.width - cardWidth - 12.0;
    left = left.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    final showAbove = tap.dy > stackSize.height * 0.55;
    final top = showAbove ? null : tap.dy + 18;
    final bottom = showAbove ? (stackSize.height - tap.dy) + 18 : null;

    final bookings = _bookingsFor(_selectedDay!);
    final blocked = _blockedFor(_selectedDay!);

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
                          _formatCardTitle(_selectedDay!, bookings.length, blocked.length),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
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
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final hb in bookings) ...[
                        _buildBookingRow(hb),
                        const Divider(height: 1),
                      ],
                      for (final bd in blocked) _buildBlockedRow(bd),
                    ],
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

  Widget _buildBlockedRow(BlockedDate blockedDate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.lightGrey,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.block_rounded,
                size: 20, color: AppColors.grey),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blockedDate.placeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Blocked by you - not bookable',
                  style: TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _savingBlock ? null : () => _unblockFromCard(blockedDate),
            child: const Text('Unblock', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  String _formatCardTitle(DateTime day, int bookingCount, int blockedCount) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final parts = <String>[];
    if (bookingCount > 0) {
      parts.add('$bookingCount booking${bookingCount == 1 ? '' : 's'}');
    }
    if (blockedCount > 0) {
      parts.add('$blockedCount blocked');
    }
    final suffix = parts.isEmpty ? '' : ' - ${parts.join(', ')}';
    return '${day.day} ${months[day.month - 1]} ${day.year}$suffix';
  }

  String _formatShortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
