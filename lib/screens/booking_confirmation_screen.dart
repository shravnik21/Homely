import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../models/place.dart';

/// Shown after the "Booking Confirmed!" dialog is dismissed.
///
/// This screen mirrors the details the user filled in on [BookingScreen]
/// (place, dates, guests, price) plus the booking reference returned by
/// [BookingService.createBooking], so the trip has a permanent-feeling
/// summary the user can screenshot or glance back at before leaving
/// the flow.
class BookingConfirmationScreen extends StatelessWidget {
  final Place place;
  final String bookingId;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final num subtotal;
  final num serviceFee;
  final num total;

  const BookingConfirmationScreen({
    super.key,
    required this.place,
    required this.bookingId,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.subtotal,
    required this.serviceFee,
    required this.total,
  });

  int get _nights => checkOut.difference(checkIn).inDays;

  String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // Short, readable reference shown to the guest - the first 8 chars
  // of the UUID, uppercased (e.g. 'A1B2C3D4'), same idea booking apps
  // use so people don't have to read a full UUID out loud.
  String get _shortRef =>
      bookingId.replaceAll('-', '').substring(0, 8).toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        automaticallyImplyLeading: false,
        title: const Text('Booking details'),
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
            const SizedBox(height: 24),
            _buildReference(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBackHomeBar(context),
    );
  }

  // ---- Green success banner at the top of the screen ----
  Widget _buildStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F8EE),
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
            child: const Icon(Icons.check_rounded,
                color: Colors.green, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\'re booked!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.dark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'A confirmation has been saved to your trips.',
                  style: TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Place photo + title + address, same info as the booking screen ----
  Widget _buildPlaceCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
              imageUrl: place.coverImage,
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
                    place.title,
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
                          '${place.address}, ${place.cityName}',
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

  // ---- Check-in / check-out / guests, exactly what was chosen on the
  // booking screen ----
  Widget _buildTripDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _detailRow('Check-in', _fmt(checkIn)),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Checkout', _fmt(checkOut)),
          const Divider(height: 22, color: AppColors.white),
          _detailRow(
              'Length of stay', '$_nights night${_nights > 1 ? 's' : ''}'),
          const Divider(height: 22, color: AppColors.white),
          _detailRow('Guests', '$guests guest${guests > 1 ? 's' : ''}'),
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

  // ---- Same price math the booking screen showed, so nothing looks
  // like it changed between screens ----
  Widget _buildPriceBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _detailRow(
              '₹${place.pricePerNight.toStringAsFixed(0)} x $_nights night${_nights > 1 ? 's' : ''}',
              '₹${subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          _detailRow('Service fee', '₹${serviceFee.toStringAsFixed(0)}'),
          const Divider(height: 24, color: AppColors.white),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total paid',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
              Text('₹${total.toStringAsFixed(0)}',
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

  // ---- Booking reference, so the user has something to quote if they
  // need support ----
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

  // ---- Bottom bar with a single way out: back to Home ----
  Widget _buildBackHomeBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            // Pop everything back to Home (past this screen, the
            // booking screen, and the place detail screen).
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('Back to Home'),
        ),
      ),
    );
  }
}
