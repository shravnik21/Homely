import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/booking.dart';
import 'package:homely_app/services/booking_service.dart';
import 'package:homely_app/widgets/error_state_view.dart';
import 'booking_detail_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final BookingService _bookingService = BookingService();
  late Future<List<Booking>> _bookingsFuture;

  @override
  void initState() {
    super.initState();
    _bookingsFuture = _bookingService.getUserBookings();
  }

  // Re-fetches the list - called after returning from the booking
  // details screen if a reschedule/cancel actually happened there,
  // so the card (dates, status, price) reflects the change.
  void _refreshBookings() {
    setState(() {
      _bookingsFuture = _bookingService.getUserBookings();
    });
  }

  Future<void> _openBookingDetails(Booking booking) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(booking: booking),
      ),
    );
    if (changed == true) _refreshBookings();
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'My Bookings',
            style: TextStyle(
              color: AppColors.dark,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          iconTheme: const IconThemeData(color: AppColors.dark),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.grey,
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
            ],
          ),
        ),
        body: FutureBuilder<List<Booking>>(
          future: _bookingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                error: snapshot.error!,
                fallbackMessage: 'Could not load bookings.',
                onRetry: _refreshBookings,
              );
            }

            final all = snapshot.data ?? [];
            final upcoming = all.where((b) => b.isUpcoming).toList();
            final past = all.where((b) => !b.isUpcoming).toList();

            return TabBarView(
              children: [
                _buildBookingList(upcoming, emptyText: 'No upcoming trips yet.\nTime to book your next stay!'),
                _buildBookingList(past, emptyText: 'No past trips yet.'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBookingList(List<Booking> bookings, {required String emptyText}) {
    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grey, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: bookings.length,
      itemBuilder: (context, index) => _BookingCard(
        booking: bookings[index],
        formatDate: _fmt,
        onTap: () => _openBookingDetails(bookings[index]),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final String Function(DateTime) formatDate;
  final VoidCallback onTap;

  const _BookingCard({
    required this.booking,
    required this.formatDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final cancelled = booking.status == 'cancelled';
    final statusLabel = cancelled
        ? 'Cancelled'
        : (booking.isUpcoming ? 'Upcoming' : 'Completed');
    final statusColor = cancelled
        ? AppColors.error
        : (booking.isUpcoming ? Colors.green : AppColors.grey);
    final statusBg = cancelled
        ? AppColors.error.withValues(alpha: 0.1)
        : (booking.isUpcoming
            ? Colors.green.withValues(alpha: 0.1)
            : AppColors.lightGrey);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
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
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: booking.coverImage,
              width: 90,
              height: 90,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 90,
                height: 90,
                color: AppColors.lightGrey,
              ),
              errorWidget: (context, url, error) => Container(
                width: 90,
                height: 90,
                color: AppColors.lightGrey,
                child: const Icon(Icons.image_not_supported_outlined,
                    color: AppColors.grey, size: 24),
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
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
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
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: AppColors.grey),
                    const SizedBox(width: 3),
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
                const SizedBox(height: 8),
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
                  '${booking.nights} night${booking.nights > 1 ? 's' : ''} · ${booking.guests} guest${booking.guests > 1 ? 's' : ''} · ₹${booking.totalPrice.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
