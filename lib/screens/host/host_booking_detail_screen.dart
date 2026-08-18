import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/services/payout_policy.dart';
import 'package:homely_app/utils/network_error_helper.dart';

/// Full-detail view for a single booking, opened by tapping a booking
/// card on [HostHomeScreen]'s "Recent Bookings" preview or on
/// [HostBookingsScreen]'s "Your Bookings" list. Mirrors the layout of
/// the guest-side BookingDetailScreen (status banner, place card,
/// trip details) but adds the host-only pieces: who the guest is and
/// how to reach them, the payout breakdown, and a private note.
class HostBookingDetailScreen extends StatefulWidget {
  final HostBooking hostBooking;

  const HostBookingDetailScreen({super.key, required this.hostBooking});

  @override
  State<HostBookingDetailScreen> createState() =>
      _HostBookingDetailScreenState();
}

class _HostBookingDetailScreenState extends State<HostBookingDetailScreen> {
  final HostBookingsService _bookingsService = HostBookingsService();

  late HostBooking _hostBooking;
  late final TextEditingController _notesController;
  bool _isSavingNotes = false;
  bool _notesDirty = false;

  @override
  void initState() {
    super.initState();
    _hostBooking = widget.hostBooking;
    _notesController = TextEditingController(text: _hostBooking.hostNotes ?? '');
    _notesController.addListener(() {
      final changed = _notesController.text.trim() != (_hostBooking.hostNotes ?? '').trim();
      if (changed != _notesDirty) setState(() => _notesDirty = changed);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get _shortRef =>
      _hostBooking.booking.id.replaceAll('-', '').substring(0, 8).toUpperCase();

  bool get _isCancelled => _hostBooking.booking.status == 'cancelled';

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _saveNotes() async {
    final newNotes = _notesController.text;
    setState(() => _isSavingNotes = true);
    try {
      await _bookingsService.updateHostNotes(
        bookingId: _hostBooking.booking.id,
        notes: newNotes,
      );
      if (!mounted) return;
      setState(() {
        _hostBooking = _hostBooking.copyWith(
          hostNotes: newNotes.trim().isEmpty ? null : newNotes.trim(),
        );
        _notesDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'Could not save note.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _hostBooking.booking;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        title: const Text('Booking details'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            _buildStatusBanner(booking),
            const SizedBox(height: 24),
            _sectionTitle('Guest'),
            const SizedBox(height: 10),
            _buildGuestCard(),
            const SizedBox(height: 24),
            _sectionTitle('Listing'),
            const SizedBox(height: 10),
            _buildPlaceCard(booking),
            const SizedBox(height: 24),
            _sectionTitle('Trip details'),
            const SizedBox(height: 10),
            _buildTripDetails(booking),
            const SizedBox(height: 24),
            _sectionTitle('Payout'),
            const SizedBox(height: 10),
            _buildPayoutBreakdown(booking),
            const SizedBox(height: 24),
            _sectionTitle('Notes'),
            const SizedBox(height: 10),
            _buildNotesSection(),
            const SizedBox(height: 20),
            _buildReference(),
          ],
        ),
      ),
    );
  }

  // ---- Status banner - green for upcoming/hosting, red for
  // cancelled, grey once completed ----
  Widget _buildStatusBanner(Booking booking) {
    final cancelled = _isCancelled;
    final bg = cancelled ? const Color(0xFFFDECEA) : const Color(0xFFE8F8EE);
    final iconColor = cancelled ? AppColors.error : Colors.green;
    final icon = cancelled ? Icons.close_rounded : Icons.check_rounded;
    final title = cancelled
        ? 'Booking cancelled'
        : (!booking.isUpcoming
            ? 'Stay completed'
            : (booking.isCheckedIn ? 'Guest checked in' : 'Booking confirmed'));
    final cancelledOnText = booking.cancelledAt != null
        ? 'Cancelled on ${_fmt(booking.cancelledAt!)}'
        : null;
    final subtitle = cancelled
        ? (booking.cancellationFee != null
            ? '${cancelledOnText != null ? '$cancelledOnText · ' : ''}'
                '${_hostBooking.guestName} cancelled'
                '${(booking.cancellationFee ?? 0) > 0 ? ' · ₹${booking.cancellationFee!.toStringAsFixed(0)} cancellation fee charged' : ' · free cancellation, no fee'}.'
            : (cancelledOnText ?? 'This booking is no longer active.'))
        : (!booking.isUpcoming
            ? 'This stay has already wrapped up.'
            : (booking.isCheckedIn
                ? '${_hostBooking.guestName} has arrived.'
                : '${_hostBooking.guestName} is booked in for this stay.'));

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

  // ---- Guest card - avatar, name, and quick contact actions ----
  Widget _buildGuestCard() {
    final hasEmail = (_hostBooking.guestEmail ?? '').trim().isNotEmpty;
    final hasPhone = (_hostBooking.guestPhone ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        children: [
          Row(
            children: [
              _buildGuestAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hostBooking.guestName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_hostBooking.booking.guests} guest${_hostBooking.booking.guests == 1 ? '' : 's'} on this trip',
                      style: const TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasEmail || hasPhone) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (hasPhone)
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.call_outlined,
                      label: 'Call',
                      onTap: () => _copyToClipboard('Phone number', _hostBooking.guestPhone!.trim()),
                    ),
                  ),
                if (hasPhone && hasEmail) const SizedBox(width: 10),
                if (hasEmail)
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.message_outlined,
                      label: 'Message',
                      onTap: () => _copyToClipboard('Email', _hostBooking.guestEmail!.trim()),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuestAvatar() {
    final url = _hostBooking.guestAvatarUrl;
    if (url != null && url.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => _buildInitialAvatar(),
        ),
      );
    }
    return _buildInitialAvatar();
  }

  Widget _buildInitialAvatar() {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
      alignment: Alignment.center,
      child: Text(
        _hostBooking.guestInitial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPlaceCard(Booking booking) {
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
              imageUrl: booking.coverImage,
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
                    booking.placeTitle,
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
                          '${booking.placeAddress}, ${booking.cityName}',
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

  Widget _buildTripDetails(Booking booking) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _detailRow('Check-in', _fmt(booking.checkIn)),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Checkout', _fmt(booking.checkOut)),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Length of stay',
              '${booking.nights} night${booking.nights > 1 ? 's' : ''}'),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Guests',
              '${booking.guests} guest${booking.guests > 1 ? 's' : ''}'),
          if (_isCancelled && booking.cancelledAt != null) ...[
            const Divider(height: 22, color: AppColors.white),
            _detailRow('Cancelled on', _fmt(booking.cancelledAt!)),
          ],
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

  // ---- Payout: what the host actually earns, distinct from the
  // guest-facing total (which includes the platform's service fee).
  // If the booking was cancelled, this instead shows what the guest
  // was charged as a cancellation fee and the host's compensation
  // for it (capped at what the stay would normally have paid out -
  // a host is never compensated for more than the booking was
  // actually worth).
  Widget _buildPayoutBreakdown(Booking booking) {
    final subtotal = PayoutPolicy.stayPayout(
      pricePerNight: booking.pricePerNight,
      nights: booking.nights,
      totalPrice: booking.totalPrice,
    );
    final serviceFee = PayoutPolicy.guestServiceFeeFor(
      totalPrice: booking.totalPrice,
      stayPayout: subtotal,
    );
    final cancelled = booking.status == 'cancelled';
    final fee = booking.cancellationFee;

    if (cancelled && fee != null) {
      final compensation = PayoutPolicy.cancellationCompensation(
        cancellationFee: fee,
        stayPayout: subtotal,
      );
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _detailRow('Guest was charged', '₹${fee.toStringAsFixed(0)} fee'),
            const SizedBox(height: 10),
            _detailRow('Guest refunded',
                '₹${(booking.refundAmount ?? (booking.totalPrice - fee)).toStringAsFixed(0)}'),
            const Divider(height: 24, color: AppColors.white),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Your compensation',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark)),
                Text('₹${compensation.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark)),
              ],
            ),
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
      child: Column(
        children: [
          if (booking.pricePerNight > 0) ...[
            _detailRow(
                '₹${booking.pricePerNight.toStringAsFixed(0)} x ${booking.nights} night${booking.nights > 1 ? 's' : ''}',
                '₹${subtotal.toStringAsFixed(0)}'),
            const SizedBox(height: 10),
            _detailRow('Guest paid total', '₹${booking.totalPrice.toStringAsFixed(0)}'),
            const SizedBox(height: 10),
            _detailRow('Platform fee', '-₹${serviceFee.toStringAsFixed(0)}'),
            const Divider(height: 24, color: AppColors.white),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your payout',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
              Text('₹${subtotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Private note, only the host ever sees this ----
  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Only you can see this - handy for things like early check-in requests.",
            style: TextStyle(fontSize: 11.5, color: AppColors.grey),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 13.5, color: AppColors.dark),
            decoration: InputDecoration(
              hintText: 'Add a note about this booking…',
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_notesDirty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isSavingNotes ? null : _saveNotes,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSavingNotes
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text('Save note'),
              ),
            ),
          ],
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
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContactButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.dark),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
