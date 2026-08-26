import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/booking_service.dart';
import 'package:homely_app/services/cancellation_policy.dart';
import 'package:homely_app/screens/guest/booking_confirmation_screen.dart';
import 'package:homely_app/screens/guest/cancellation_policy_detail_screen.dart';
import 'package:homely_app/widgets/availability_date_range_sheet.dart';
import 'package:homely_app/utils/network_error_helper.dart';

class BookingScreen extends StatefulWidget {
  final Place place;

  const BookingScreen({super.key, required this.place});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final BookingService _bookingService = BookingService();

  DateTime? _checkIn;
  DateTime? _checkOut;
  int _guests = 1;
  bool _isBooking = false;

  int get _nights =>
      (_checkIn != null && _checkOut != null)
          ? _checkOut!.difference(_checkIn!).inDays
          : 0;

  num get _subtotal => _nights * widget.place.pricePerNight;
  num get _serviceFee => (_subtotal * 0.05); // flat 5% service fee
  num get _total => _subtotal + _serviceFee;

  bool get _canConfirm => _nights > 0 && !_isBooking;

  String _fmt(DateTime? d) {
    if (d == null) return 'Add date';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  // ---- The curved bottom-sheet calendar, Airbnb-style, with dates
  // someone else already booked greyed out and unselectable ----
  Future<void> _openDatePicker() async {
    final range = await showAvailabilityDatePicker(
      context: context,
      placeId: widget.place.id,
      title: 'Select dates',
      saveLabel: 'Save dates',
      initialStart: _checkIn,
      initialEnd: _checkOut,
    );
    if (range == null) return;
    setState(() {
      _checkIn = range.start;
      _checkOut = range.end;
    });
  }

  Future<void> _confirmBooking() async {
    setState(() => _isBooking = true);
    try {
      final bookingId = await _bookingService.createBooking(
        placeId: widget.place.id,
        checkIn: _checkIn!,
        checkOut: _checkOut!,
        guests: _guests,
        totalPrice: _total,
      );
      if (!mounted) return;
      _showSuccessDialog(bookingId);
    } catch (e) {
      if (!mounted) return;
      // A BookingConflictException means someone else grabbed these
      // exact dates between us loading the calendar and confirming -
      // the DB's no_overlapping_bookings constraint (see
      // schema_no_overlapping_bookings.sql) is what actually caught
      // it. Clear the picked dates so the guest can't just tap
      // "Confirm" again and hit the same wall.
      final isConflict = e is BookingConflictException;
      if (isConflict) {
        setState(() {
          _checkIn = null;
          _checkOut = null;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isConflict ? e.toString() : friendlyError(e, fallback: 'Booking failed.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  void _showSuccessDialog(String bookingId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F8EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.green, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Booking Confirmed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.place.title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmt(_checkIn)} - ${_fmt(_checkOut)} · $_nights night${_nights > 1 ? 's' : ''}',
              style: const TextStyle(
                  color: AppColors.dark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Close the dialog first, then replace this booking
                  // screen with the confirmation screen so the user
                  // can't swipe/back into the booking form again -
                  // "Back to Home" on that screen is now the only way
                  // out of the flow.
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => BookingConfirmationScreen(
                        place: widget.place,
                        bookingId: bookingId,
                        checkIn: _checkIn!,
                        checkOut: _checkOut!,
                        guests: _guests,
                        subtotal: _subtotal,
                        serviceFee: _serviceFee,
                        total: _total,
                      ),
                    ),
                  );
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
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
        title: const Text('Confirm and book'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.place.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.place.address}, ${widget.place.cityName}',
              style: const TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            const Text(
              'Trip dates',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark),
            ),
            const SizedBox(height: 10),
            _buildDateSelector(),

            const SizedBox(height: 24),
            const Text(
              'Guests',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark),
            ),
            const SizedBox(height: 10),
            _buildGuestStepper(),

            const SizedBox(height: 28),
            const Text(
              'Price details',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark),
            ),
            const SizedBox(height: 10),
            _buildPriceBreakdown(),

            const SizedBox(height: 28),
            _buildCancellationWarning(),
          ],
        ),
      ),
      bottomNavigationBar: _buildConfirmBar(),
    );
  }

  // ---- Replaces the old full policy breakdown that used to live on
  // this screen - a tappable warning instead, so the guest is
  // prompted to actually go read the listing's specific policy (see
  // PlaceDetailScreen's card / CancellationPolicyDetailScreen) rather
  // than skimming past a wall of text before every booking. ----
  Widget _buildCancellationWarning() {
    final type =
        CancellationPolicyTypeX.fromDb(widget.place.cancellationPolicyType);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CancellationPolicyDetailScreen(place: widget.place),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Review the cancellation policy',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Make sure you're comfortable with this listing's "
                    "${type.label} cancellation terms before you book.",
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.grey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Text(
                        'View cancellation policy',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: _openDatePicker,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHECK-IN',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.grey,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_fmt(_checkIn),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark)),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 44, color: AppColors.white),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHECKOUT',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.grey,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_fmt(_checkOut),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Guests',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.dark)),
              Text('Max ${widget.place.maxGuests} guests',
                  style:
                      const TextStyle(color: AppColors.grey, fontSize: 12)),
            ],
          ),
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove,
                onTap: _guests > 1
                    ? () => setState(() => _guests--)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$_guests',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              _StepperButton(
                icon: Icons.add,
                onTap: _guests < widget.place.maxGuests
                    ? () => setState(() => _guests++)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    if (_nights == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Select your trip dates to see the price breakdown.',
          style: TextStyle(color: AppColors.grey, fontSize: 13),
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
          _priceRow(
              '₹${widget.place.pricePerNight.toStringAsFixed(0)} x $_nights night${_nights > 1 ? 's' : ''}',
              '₹${_subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          _priceRow('Service fee', '₹${_serviceFee.toStringAsFixed(0)}'),
          const Divider(height: 24, color: AppColors.white),
          _priceRow('Total', '₹${_total.toStringAsFixed(0)}', bold: true),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: bold ? AppColors.dark : AppColors.grey,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }

  Widget _buildConfirmBar() {
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
          onPressed: _canConfirm ? _confirmBooking : null,
          child: _isBooking
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Text(_nights > 0
                  ? 'Confirm Booking · ₹${_total.toStringAsFixed(0)}'
                  : 'Select dates to continue'),
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : AppColors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 16, color: enabled ? Colors.white : AppColors.grey),
      ),
    );
  }
}

