import 'package:homely_app/models/host_booking.dart';
import 'package:homely_app/services/payout_policy.dart';

/// Whether a line item's money has actually landed with the host yet.
enum PayoutStatus { paidOut, upcoming }

/// What kind of booking event this earning came from.
enum EarningType { stay, cancellationCompensation }

/// One row in the host's earnings ledger - either a stay (completed
/// or still upcoming) or the compensation paid out for a guest's
/// cancellation fee. Built fresh from a [HostBooking] every time the
/// Earnings screen loads rather than stored anywhere separately -
/// same reasoning as [PayoutPolicy] itself: `bookings` is already the
/// source of truth, this just reshapes it for display.
class EarningLineItem {
  final String bookingId;
  final String placeId;
  final String placeTitle;
  final String coverImage;
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final EarningType type;
  final PayoutStatus status;
  // The guest-facing amount this line item is based on - the full
  // booking total for a stay, or the cancellation fee charged for
  // compensation.
  final num grossAmount;
  // Homely's guest-side service fee, informational only - never
  // actually deducted from the host. Zero for cancellation
  // compensation (no separate fee concept there).
  final num guestServiceFee;
  final num netAmount;
  // Drives both "newest first" sorting and the monthly chart -
  // check-out date for a stay (when it actually finished earning),
  // the cancellation date for compensation (when it was charged).
  final DateTime earningDate;

  const EarningLineItem({
    required this.bookingId,
    required this.placeId,
    required this.placeTitle,
    required this.coverImage,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.type,
    required this.status,
    required this.grossAmount,
    required this.guestServiceFee,
    required this.netAmount,
    required this.earningDate,
  });
}

class MonthlyEarning {
  final DateTime month; // normalized to the 1st, for labels/sorting
  final num net;
  const MonthlyEarning({required this.month, required this.net});
}

class ListingEarning {
  final String placeId;
  final String placeTitle;
  final num net;
  const ListingEarning({
    required this.placeId,
    required this.placeTitle,
    required this.net,
  });
}

/// Aggregated earnings across every listing a host owns, plus the
/// full ledger of line items backing those totals.
class EarningsSummary {
  final List<EarningLineItem> lineItems;
  final num totalPaidOut;
  final num totalUpcoming;
  final num totalGuestPayments; // gross, across active + cancelled-with-fee
  final num totalGuestServiceFees;
  final List<MonthlyEarning> lastSixMonths;
  final List<ListingEarning> byListing;

  const EarningsSummary({
    required this.lineItems,
    required this.totalPaidOut,
    required this.totalUpcoming,
    required this.totalGuestPayments,
    required this.totalGuestServiceFees,
    required this.lastSixMonths,
    required this.byListing,
  });

  /// What the dashboard's "Earnings" stat card shows - everything
  /// already paid out, plus what's on its way once guests check out.
  num get totalNet => totalPaidOut + totalUpcoming;

  factory EarningsSummary.empty() => const EarningsSummary(
        lineItems: [],
        totalPaidOut: 0,
        totalUpcoming: 0,
        totalGuestPayments: 0,
        totalGuestServiceFees: 0,
        lastSixMonths: [],
        byListing: [],
      );

  factory EarningsSummary.fromBookings(List<HostBooking> hostBookings) {
    final items = <EarningLineItem>[];

    for (final hb in hostBookings) {
      final b = hb.booking;

      if (b.status == 'cancelled') {
        final fee = b.cancellationFee;
        final cancelledAt = b.cancelledAt;
        // Only a fee > 0 (the partial/no-refund tiers) means there's
        // anything to compensate the host with - a free cancellation
        // (15+ days out) earns nothing, since nobody was charged.
        if (fee != null && fee > 0 && cancelledAt != null) {
          final stayPayout = PayoutPolicy.stayPayout(
            pricePerNight: b.pricePerNight,
            nights: b.nights,
            totalPrice: b.totalPrice,
          );
          final compensation = PayoutPolicy.cancellationCompensation(
            cancellationFee: fee,
            stayPayout: stayPayout,
          );
          items.add(EarningLineItem(
            bookingId: b.id,
            placeId: b.placeId,
            placeTitle: b.placeTitle,
            coverImage: b.coverImage,
            guestName: hb.guestName,
            checkIn: b.checkIn,
            checkOut: b.checkOut,
            type: EarningType.cancellationCompensation,
            // Settled the moment the cancellation happened - unlike
            // a stay, there's nothing left to wait on.
            status: PayoutStatus.paidOut,
            grossAmount: fee,
            guestServiceFee: 0,
            netAmount: compensation,
            earningDate: cancelledAt,
          ));
        }
        continue;
      }

      // Active (non-cancelled) booking - a real or upcoming stay.
      final stayPayout = PayoutPolicy.stayPayout(
        pricePerNight: b.pricePerNight,
        nights: b.nights,
        totalPrice: b.totalPrice,
      );
      items.add(EarningLineItem(
        bookingId: b.id,
        placeId: b.placeId,
        placeTitle: b.placeTitle,
        coverImage: b.coverImage,
        guestName: hb.guestName,
        checkIn: b.checkIn,
        checkOut: b.checkOut,
        type: EarningType.stay,
        status: b.isUpcoming ? PayoutStatus.upcoming : PayoutStatus.paidOut,
        grossAmount: b.totalPrice,
        guestServiceFee: PayoutPolicy.guestServiceFeeFor(
          totalPrice: b.totalPrice,
          stayPayout: stayPayout,
        ),
        netAmount: stayPayout,
        earningDate: b.checkOut,
      ));
    }

    items.sort((a, b) => b.earningDate.compareTo(a.earningDate));

    num paidOut = 0, upcoming = 0, gross = 0, fees = 0;
    for (final i in items) {
      gross += i.grossAmount;
      fees += i.guestServiceFee;
      if (i.status == PayoutStatus.paidOut) {
        paidOut += i.netAmount;
      } else {
        upcoming += i.netAmount;
      }
    }

    // Last 6 months, oldest first, for the trend chart. Dart's
    // DateTime constructor normalizes an out-of-range month (e.g.
    // month 0 or -1), so this correctly walks back across a year
    // boundary without any special-casing.
    final now = DateTime.now();
    final months = List.generate(
      6,
      (i) => DateTime(now.year, now.month - (5 - i), 1),
    );
    final monthlyTotals = <DateTime, num>{for (final m in months) m: 0};
    for (final i in items) {
      final key = DateTime(i.earningDate.year, i.earningDate.month, 1);
      if (monthlyTotals.containsKey(key)) {
        monthlyTotals[key] = monthlyTotals[key]! + i.netAmount;
      }
    }
    final lastSixMonths = months
        .map((m) => MonthlyEarning(month: m, net: monthlyTotals[m] ?? 0))
        .toList();

    // Per-listing breakdown, highest earner first.
    final listingTotals = <String, num>{};
    final listingTitles = <String, String>{};
    for (final i in items) {
      listingTotals[i.placeId] = (listingTotals[i.placeId] ?? 0) + i.netAmount;
      listingTitles[i.placeId] = i.placeTitle;
    }
    final byListing = listingTotals.entries
        .where((e) => e.value > 0)
        .map((e) => ListingEarning(
              placeId: e.key,
              placeTitle: listingTitles[e.key] ?? 'Listing',
              net: e.value,
            ))
        .toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    return EarningsSummary(
      lineItems: items,
      totalPaidOut: paidOut,
      totalUpcoming: upcoming,
      totalGuestPayments: gross,
      totalGuestServiceFees: fees,
      lastSixMonths: lastSixMonths,
      byListing: byListing,
    );
  }
}
