import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/models/review.dart';
import 'package:homely_app/services/booking_service.dart';
import 'package:homely_app/services/cancellation_policy.dart';
import 'package:homely_app/services/review_service.dart';
import 'package:homely_app/screens/guest/write_review_screen.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'package:homely_app/widgets/star_rating.dart';

/// Full-detail view for a single booking, opened by tapping a card on
/// [MyBookingsScreen]. Mirrors the layout of [BookingConfirmationScreen]
/// (same info, same styling) but adds a "Manage booking" action that
/// lets the guest reschedule the dates or cancel outright.
///
/// Pops with `true` when the booking was changed (rescheduled or
/// cancelled) so [MyBookingsScreen] knows to refresh its list.
class BookingDetailScreen extends StatefulWidget {
  final Booking booking;

  const BookingDetailScreen({super.key, required this.booking});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final BookingService _bookingService = BookingService();
  final ReviewService _reviewService = ReviewService();

  late Booking _booking;
  bool _isUpdating = false;
  // Tracks whether we've changed anything, so we know whether to pop
  // with `true` (refresh the list behind us) or just `false`.
  bool _didChange = false;

  // Only relevant once the stay is completed - null while loading,
  // stays null (no error state needed) if the lookup fails, since
  // this is a "nice to have" section, not core booking info.
  Review? _existingReview;
  bool _isLoadingReview = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    if (_isCompleted) _loadExistingReview();
  }

  Future<void> _loadExistingReview() async {
    setState(() => _isLoadingReview = true);
    try {
      final review = await _reviewService.getReviewForBooking(_booking.id);
      if (!mounted) return;
      setState(() => _existingReview = review);
    } catch (_) {
      // Non-critical - the "Leave a review" CTA just won't show if
      // this fails, rather than blocking the rest of the screen.
    } finally {
      if (mounted) setState(() => _isLoadingReview = false);
    }
  }

  Future<void> _openWriteReview() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WriteReviewScreen(booking: _booking),
      ),
    );
    if (submitted == true) _loadExistingReview();
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get _shortRef =>
      _booking.id.replaceAll('-', '').substring(0, 8).toUpperCase();

  bool get _isCancelled => _booking.status == 'cancelled';

  // A booking can only be managed while it's confirmed and still in
  // the future - once it's cancelled, or already completed, there's
  // nothing left to reschedule or cancel.
  bool get _canManage => !_isCancelled && _booking.isUpcoming;

  // A stay is eligible for a review once it's genuinely over - not
  // cancelled, and checkout has passed. Mirrors the same condition
  // schema_reviews.sql's insert policy enforces server-side.
  bool get _isCompleted => !_isCancelled && !_booking.isUpcoming;

  @override
  Widget build(BuildContext context) {
    // PopScope (rather than the deprecated WillPopScope) intercepts
    // both the appbar back button and the system back
    // gesture/button, so a reschedule/cancel made here is reflected
    // however the user leaves this screen.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_didChange);
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          foregroundColor: AppColors.dark,
          title: const Text('Booking details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_didChange),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              _buildStatusBanner(),
              const SizedBox(height: 24),
              _buildPlaceCard(),
              const SizedBox(height: 24),
              _sectionTitle('Trip details'),
              const SizedBox(height: 10),
              _buildTripDetails(),
              const SizedBox(height: 24),
              _sectionTitle('Price details'),
              const SizedBox(height: 10),
              _buildPriceBreakdown(),
              if (_isCompleted) ...[
                const SizedBox(height: 24),
                _buildReviewSection(),
              ],
              const SizedBox(height: 24),
              _buildReference(),
            ],
          ),
        ),
        bottomNavigationBar: _canManage ? _buildManageBar() : null,
      ),
    );
  }

  // ---- Status banner - green for upcoming, red for cancelled ----
  Widget _buildStatusBanner() {
    final cancelled = _isCancelled;
    final bg = cancelled ? const Color(0xFFFDECEA) : const Color(0xFFE8F8EE);
    final iconColor = cancelled ? AppColors.error : Colors.green;
    final icon = cancelled ? Icons.close_rounded : Icons.check_rounded;
    final title = cancelled
        ? 'Booking cancelled'
        : (_booking.isUpcoming ? 'Booking confirmed' : 'Trip completed');
    final subtitle = cancelled
        ? (_booking.refundAmount != null
            ? '₹${_booking.refundAmount!.toStringAsFixed(0)} refunded'
                '${(_booking.cancellationFee ?? 0) > 0 ? ' · ₹${_booking.cancellationFee!.toStringAsFixed(0)} cancellation fee' : ''}.'
            : 'This booking is no longer active.')
        : (_booking.isUpcoming
            ? 'You\'re all set for this stay.'
            : 'We hope you enjoyed your stay.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            child: CachedNetworkImage(
              imageUrl: _booking.coverImage,
              height: 96,
              width: 96,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                height: 96,
                width: 96,
                color: AppColors.lightGrey,
              ),
              errorWidget: (context, url, error) => Container(
                height: 96,
                width: 96,
                color: AppColors.lightGrey,
                child: const Icon(Icons.image_not_supported_outlined,
                    color: AppColors.grey),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _booking.placeTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${_booking.placeAddress}, ${_booking.cityName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.dark),
      );

  Widget _buildTripDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _detailRow('Check-in', _fmt(_booking.checkIn)),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Checkout', _fmt(_booking.checkOut)),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Length of stay',
              '${_booking.nights} night${_booking.nights > 1 ? 's' : ''}'),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Guests',
              '${_booking.guests} guest${_booking.guests > 1 ? 's' : ''}'),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                color: AppColors.dark,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPriceBreakdown() {
    final subtotal = _booking.pricePerNight * _booking.nights;
    final serviceFee = _booking.totalPrice - subtotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (_booking.pricePerNight > 0) ...[
            _detailRow(
                '₹${_booking.pricePerNight.toStringAsFixed(0)} x ${_booking.nights} night${_booking.nights > 1 ? 's' : ''}',
                '₹${subtotal.toStringAsFixed(0)}'),
            const SizedBox(height: 10),
            _detailRow('Service fee', '₹${serviceFee.toStringAsFixed(0)}'),
            const Divider(height: 24, color: AppColors.white),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total paid',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
              Text('₹${_booking.totalPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
            ],
          ),
          if (_isCancelled && _booking.refundAmount != null) ...[
            const Divider(height: 24, color: AppColors.white),
            if ((_booking.cancellationFee ?? 0) > 0) ...[
              _detailRow('Cancellation fee',
                  '₹${_booking.cancellationFee!.toStringAsFixed(0)}'),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Refunded',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark)),
                Text('₹${_booking.refundAmount!.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---- Review section - only shown once the stay is completed.
  // Shows a "Leave a review" prompt if the guest hasn't reviewed yet,
  // or their existing rating + comment if they have. ----
  Widget _buildReviewSection() {
    if (_isLoadingReview) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final review = _existingReview;
    if (review != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Your review',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.dark),
                ),
                const Spacer(),
                StarRatingDisplay(rating: review.rating.toDouble(), size: 16),
              ],
            ),
            if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                review.comment!,
                style: const TextStyle(fontSize: 13, color: AppColors.grey, height: 1.4),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How was your stay?',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.dark),
                ),
                SizedBox(height: 3),
                Text(
                  'Leave a review to help future guests.',
                  style: TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _openWriteReview,
            child: const Text('Leave a review'),
          ),
        ],
      ),
    );
  }

  Widget _buildReference() {
    return Center(
      child: Text(
        'Booking reference · $_shortRef',
        style: const TextStyle(
            color: AppColors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5),
      ),
    );
  }

  // ---- Bottom "Manage booking" bar - only shown while there's
  // something left to manage ----
  Widget _buildManageBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isUpdating ? null : _openManageSheet,
          child: _isUpdating
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : const Text('Manage booking'),
        ),
      ),
    );
  }

  // ---- Tapping "Manage booking" opens a sheet with the two actions ----
  Future<void> _openManageSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Manage booking',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark),
                  ),
                ),
                const SizedBox(height: 8),
                _ManageOptionTile(
                  icon: Icons.calendar_month_outlined,
                  title: 'Reschedule',
                  subtitle: 'Change your check-in and checkout dates',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openReschedulePicker();
                  },
                ),
                const SizedBox(height: 8),
                _ManageOptionTile(
                  icon: Icons.cancel_outlined,
                  title: 'Cancel booking',
                  subtitle: 'Cancel this stay',
                  iconColor: AppColors.error,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmCancel();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Reschedule: same curved-calendar bottom sheet the initial
  // booking flow uses on [BookingScreen], pre-seeded with the
  // existing dates ----
  Future<void> _openReschedulePicker() async {
    DateTime? tempStart = _booking.checkIn;
    DateTime? tempEnd = _booking.checkOut;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Reschedule dates',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TableCalendar(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: tempStart ?? DateTime.now(),
                      rangeStartDay: tempStart,
                      rangeEndDay: tempEnd,
                      rangeSelectionMode: RangeSelectionMode.toggledOn,
                      calendarFormat: CalendarFormat.month,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      calendarStyle: const CalendarStyle(
                        rangeStartDecoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        rangeEndDecoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        withinRangeDecoration: BoxDecoration(
                          color: Color(0x22FF385C),
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: AppColors.lightGrey,
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: TextStyle(color: AppColors.dark),
                      ),
                      onRangeSelected: (start, end, focusedDay) {
                        setSheetState(() {
                          tempStart = start;
                          tempEnd = end;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (tempStart != null && tempEnd != null)
                            ? () {
                                Navigator.of(sheetContext).pop();
                                _submitReschedule(tempStart!, tempEnd!);
                              }
                            : null,
                        child: const Text('Save new dates'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitReschedule(DateTime newCheckIn, DateTime newCheckOut) async {
    final nights = newCheckOut.difference(newCheckIn).inDays;
    if (nights <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout must be after check-in.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Recompute total price the same way BookingScreen does (5% flat
    // service fee on top of nights x price-per-night) so a longer or
    // shorter stay is billed correctly.
    final subtotal = _booking.pricePerNight * nights;
    final serviceFee = subtotal * 0.05;
    final newTotal = subtotal + serviceFee;

    // Captured before the update below so we still have the "old"
    // dates once _booking is reassigned to the new ones.
    final previousCheckIn = _booking.checkIn;
    final previousCheckOut = _booking.checkOut;

    setState(() => _isUpdating = true);
    try {
      await _bookingService.rescheduleBooking(
        bookingId: _booking.id,
        checkIn: newCheckIn,
        checkOut: newCheckOut,
        totalPrice: newTotal,
        previousCheckIn: previousCheckIn,
        previousCheckOut: previousCheckOut,
      );
      if (!mounted) return;
      final rescheduledAt = DateTime.now();
      setState(() {
        _booking = _booking.copyWith(
          checkIn: newCheckIn,
          checkOut: newCheckOut,
          totalPrice: newTotal,
          rescheduledAt: rescheduledAt,
          previousCheckIn: previousCheckIn,
          previousCheckOut: previousCheckOut,
        );
        _didChange = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking rescheduled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'Could not reschedule.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ---- Cancel: show the real fee/refund breakdown first, this
  // can't be undone ----
  Future<void> _confirmCancel() async {
    final quote = CancellationPolicy.quote(
      checkIn: _booking.checkIn,
      totalPrice: _booking.totalPrice,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel this booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              quote.headline,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: quote.hasFee ? AppColors.error : Colors.green[700],
              ),
            ),
            const SizedBox(height: 6),
            Text(quote.explanation, style: const TextStyle(fontSize: 13)),
            if (quote.hasFee) ...[
              const SizedBox(height: 14),
              _cancelQuoteRow('Cancellation fee', quote.fee),
              const SizedBox(height: 4),
              _cancelQuoteRow("You'll be refunded", quote.refund),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep booking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);
    try {
      await _bookingService.cancelBooking(
        _booking.id,
        fee: quote.fee,
        refund: quote.refund,
      );
      if (!mounted) return;
      setState(() {
        _booking = _booking.copyWith(
          status: 'cancelled',
          cancellationFee: quote.fee,
          refundAmount: quote.refund,
          cancelledAt: DateTime.now(),
        );
        _didChange = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            quote.hasFee
                ? 'Booking cancelled. ₹${quote.refund.toStringAsFixed(0)} will be refunded.'
                : 'Booking cancelled. You\'ll be fully refunded.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'Could not cancel.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _cancelQuoteRow(String label, num amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.grey)),
        Text(
          '₹${amount.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark),
        ),
      ],
    );
  }
}

class _ManageOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  const _ManageOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.dark)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey),
          ],
        ),
      ),
    );
  }
}
