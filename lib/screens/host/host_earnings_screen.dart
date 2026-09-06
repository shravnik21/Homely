import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/earnings_summary.dart';
import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/services/host_bookings_service.dart';
import 'package:homely_app/services/host_service.dart';
import 'package:homely_app/services/payout_policy.dart';
import 'package:homely_app/screens/host/host_booking_detail_screen.dart';
import 'package:homely_app/screens/host/host_payout_details_screen.dart';
import 'package:homely_app/utils/auto_reload_on_reconnect.dart';
import 'package:homely_app/utils/currency_format.dart';
import 'package:homely_app/utils/network_retry.dart';
import 'package:homely_app/widgets/error_state_view.dart';

class _EarningsData {
  final List<HostBooking> bookings;
  final bool payoutSetupComplete;
  const _EarningsData({
    required this.bookings,
    required this.payoutSetupComplete,
  });
}

/// Full earnings breakdown for the host - opened by tapping the
/// "Earnings" stat card on [HostHomeScreen]. Shows what's already
/// been paid out, what's still upcoming, a 6-month trend, a
/// per-listing split, and a full ledger of every stay/cancellation
/// that contributed to the total, each of which opens back into
/// [HostBookingDetailScreen] for the full context.
class HostEarningsScreen extends StatefulWidget {
  const HostEarningsScreen({super.key});

  @override
  State<HostEarningsScreen> createState() => _HostEarningsScreenState();
}

class _HostEarningsScreenState extends State<HostEarningsScreen>
    with AutoReloadOnReconnectMixin {
  final HostBookingsService _bookingsService = HostBookingsService();
  final HostService _hostService = HostService();

  late Future<_EarningsData> _dataFuture;

  // 'all' or a placeId - filters the ledger list at the bottom.
  String _selectedListingFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
    startAutoReloadOnReconnect();
  }

  void _load() {
    setState(() {
      _dataFuture = withRetry(() => Future.wait([
            _bookingsService.getBookingsForMyListings(),
            _hostService.getHostSetupStatus(),
          ]).then((results) => _EarningsData(
                bookings: results[0] as List<HostBooking>,
                payoutSetupComplete: ((results[1] as Map<String, dynamic>?)
                        ?['payout_setup_complete'] as bool?) ??
                    false,
              )));
    });
  }

  @override
  void onReconnected() => _load();

  @override
  void dispose() {
    disposeAutoReloadOnReconnect();
    super.dispose();
  }

  Future<void> _openBooking(HostBooking hostBooking) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostBookingDetailScreen(hostBooking: hostBooking),
      ),
    );
    _load();
  }

  Future<void> _openPayoutSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostPayoutDetailsScreen()),
    );
    _load();
  }

  String _fmtShort(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.dark,
        title: const Text(
          'Earnings',
          style: TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<_EarningsData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                error: snapshot.error!,
                fallbackMessage: 'Could not load your earnings.',
                onRetry: _load,
              );
            }

            final data = snapshot.data ??
                const _EarningsData(bookings: [], payoutSetupComplete: false);
            final summary = EarningsSummary.fromBookings(data.bookings);
            final bookingById = {
              for (final hb in data.bookings) hb.booking.id: hb,
            };

            final filteredItems = _selectedListingFilter == 'all'
                ? summary.lineItems
                : summary.lineItems
                    .where((i) => i.placeId == _selectedListingFilter)
                    .toList();

            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (!data.payoutSetupComplete) ...[
                    _buildPayoutSetupBanner(),
                    const SizedBox(height: 16),
                  ],
                  _buildHeroCard(summary),
                  const SizedBox(height: 28),
                  if (summary.lineItems.isEmpty)
                    _buildEmptyState()
                  else ...[
                    _sectionTitle('Last 6 months'),
                    const SizedBox(height: 12),
                    _buildMonthlyChart(summary),
                    const SizedBox(height: 28),
                    if (summary.byListing.isNotEmpty) ...[
                      _sectionTitle('Earnings by listing'),
                      const SizedBox(height: 12),
                      _buildListingBreakdown(summary),
                      const SizedBox(height: 28),
                    ],
                    _buildHowItWorksCard(),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionTitle('All earnings'),
                        Text(
                          '${filteredItems.length} '
                          '${filteredItems.length == 1 ? 'entry' : 'entries'}',
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12.5),
                        ),
                      ],
                    ),
                    if (summary.byListing.length > 1) ...[
                      const SizedBox(height: 12),
                      _buildListingFilterChips(summary),
                    ],
                    const SizedBox(height: 12),
                    ...filteredItems.map((item) => _buildLedgerRow(
                          item,
                          onTap: bookingById.containsKey(item.bookingId)
                              ? () =>
                                  _openBooking(bookingById[item.bookingId]!)
                              : null,
                        )),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------- Hero + setup banner ----------------

  Widget _buildPayoutSetupBanner() {
    return GestureDetector(
      onTap: _openPayoutSetup,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.account_balance_outlined,
                color: Colors.orange[800], size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your payout details',
                    style: TextStyle(
                      color: Colors.orange[900],
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'So we know where to send your earnings once they\'re paid out.',
                    style: TextStyle(color: Colors.orange[800], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.orange[800], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(EarningsSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total earnings',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            formatInr(summary.totalNet),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  label: 'Paid out',
                  value: formatInr(summary.totalPaidOut),
                  dotColor: Colors.greenAccent[400]!,
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: _heroStat(
                  label: 'Upcoming',
                  value: formatInr(summary.totalUpcoming),
                  dotColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat({
    required String label,
    required String value,
    required Color dotColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_outlined, color: AppColors.grey, size: 32),
          SizedBox(height: 12),
          Text(
            'No earnings yet',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.dark),
          ),
          SizedBox(height: 6),
          Text(
            'Once a guest books and checks out of one of your places, '
            'your payout will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.grey, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.dark,
        ),
      );

  // ---------------- Monthly chart ----------------

  Widget _buildMonthlyChart(EarningsSummary summary) {
    final months = summary.lastSixMonths;
    final maxVal = months.fold<num>(
        0, (max, m) => m.net > max ? m.net : max);
    const chartHeight = 110.0;
    const monthLabels = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: months.map((m) {
          final heightFactor = maxVal > 0 ? (m.net / maxVal) : 0.0;
          final barHeight = (heightFactor * chartHeight).clamp(4.0, chartHeight);
          final isCurrentMonth = m.month.year == DateTime.now().year &&
              m.month.month == DateTime.now().month;
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.net > 0 ? formatInrCompact(m.net) : '',
                  style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.grey,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: chartHeight,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: barHeight,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isCurrentMonth
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  monthLabels[m.month.month - 1],
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrentMonth ? AppColors.dark : AppColors.grey,
                    fontWeight:
                        isCurrentMonth ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------- Per-listing breakdown ----------------

  Widget _buildListingBreakdown(EarningsSummary summary) {
    final maxVal = summary.byListing.first.net;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: summary.byListing.map((l) {
          final fraction = maxVal > 0 ? (l.net / maxVal) : 0.0;
          final isLast = l == summary.byListing.last;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l.placeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatInr(l.net),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.dark),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.white,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------- How payouts work ----------------

  Widget _buildHowItWorksCard() {
    final feePct = (PayoutPolicy.guestServiceFeeRate * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 17, color: AppColors.dark),
              SizedBox(width: 8),
              Text(
                'How your payout is calculated',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.dark),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoLine(
            'Guests pay a $feePct% service fee on top of your nightly rate '
            "- that's Homely's fee, not deducted from you. You keep 100% of "
            'your nightly rate.',
          ),
          const SizedBox(height: 8),
          _infoLine(
            "A stay's payout is released once the guest checks out, so it "
            'shows as "Upcoming" until then.',
          ),
          const SizedBox(height: 8),
          _infoLine(
            "If a guest cancels and is charged a fee, you're compensated "
            'for it - capped at what the stay would have earned you.',
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String text) => Text(
        text,
        style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.45),
      );

  // ---------------- Ledger ----------------

  Widget _buildListingFilterChips(EarningsSummary summary) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('all', 'All'),
          for (final l in summary.byListing)
            _filterChip(l.placeId, l.placeTitle),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _selectedListingFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.dark,
          ),
        ),
        selected: selected,
        onSelected: (_) => setState(() => _selectedListingFilter = value),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.lightGrey,
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildLedgerRow(EarningLineItem item, {VoidCallback? onTap}) {
    final isCancellation = item.type == EarningType.cancellationCompensation;
    final isUpcoming = item.status == PayoutStatus.upcoming;
    final statusColor = isUpcoming ? AppColors.primary : Colors.green[700]!;
    final statusLabel = isUpcoming ? 'Upcoming' : 'Paid out';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightGrey, width: 1.4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: item.coverImage,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(width: 48, height: 48, color: AppColors.lightGrey),
                errorWidget: (context, url, error) => Container(
                  width: 48,
                  height: 48,
                  color: AppColors.lightGrey,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: AppColors.grey, size: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.placeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
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
                  const SizedBox(height: 3),
                  Text(
                    isCancellation
                        ? '${item.guestName} · cancellation compensation'
                        : item.guestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        isCancellation
                            ? Icons.cancel_outlined
                            : Icons.calendar_today_outlined,
                        size: 12,
                        color: AppColors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${_fmtShort(item.checkIn)} - ${_fmtShort(item.checkOut)}',
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              formatInr(item.netAmount),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
