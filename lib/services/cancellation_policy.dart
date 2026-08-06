/// Homely's cancellation policy - a single, app-wide sliding scale
/// (the app doesn't yet support a host picking a per-listing policy
/// the way Airbnb does with Flexible/Moderate/Firm, so this is one
/// consistent rule everyone can rely on).
///
/// Tiers, based on days between "now" and check-in:
///   - 15+ days out  -> full refund, no fee
///   - 2-14 days out -> 50% fee (guest is refunded the other 50%)
///   - 0-1 days out  -> 100% fee, no refund (cancelling the day of
///                      check-in or the day before it - the host has
///                      essentially no chance left to rebook the
///                      dates)
///
/// A cancellation is priced at the moment it happens - once applied,
/// the fee/refund are stored on the booking row itself
/// (`cancellation_fee` / `refund_amount`) rather than recomputed
/// later, so the numbers a guest and host see stay stable even if
/// this policy changes in a future release.
class CancellationPolicy {
  const CancellationPolicy._();

  static const int fullRefundThresholdDays = 15;
  static const int noRefundThresholdDays = 2;
  static const double partialRefundFeeRate = 0.5;

  /// Whole calendar days between now and check-in. Negative once
  /// check-in has already passed.
  static int daysUntilCheckIn(DateTime checkIn) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkInDay = DateTime(checkIn.year, checkIn.month, checkIn.day);
    return checkInDay.difference(today).inDays;
  }

  /// Computes what cancelling right now would cost, for a booking
  /// worth [totalPrice] and checking in on [checkIn].
  static CancellationQuote quote({
    required DateTime checkIn,
    required num totalPrice,
  }) {
    final days = daysUntilCheckIn(checkIn);

    late final double feeRate;
    late final CancellationTier tier;
    if (days >= fullRefundThresholdDays) {
      feeRate = 0.0;
      tier = CancellationTier.free;
    } else if (days >= noRefundThresholdDays) {
      feeRate = partialRefundFeeRate;
      tier = CancellationTier.partial;
    } else {
      // Day of check-in (0) or the day before (1).
      feeRate = 1.0;
      tier = CancellationTier.none;
    }

    final fee = totalPrice * feeRate;
    final refund = totalPrice - fee;
    return CancellationQuote(
      tier: tier,
      daysUntilCheckIn: days,
      fee: fee,
      refund: refund,
      totalPrice: totalPrice,
    );
  }
}

enum CancellationTier { free, partial, none }

class CancellationQuote {
  final CancellationTier tier;
  final int daysUntilCheckIn;
  final num fee;
  final num refund;
  final num totalPrice;

  const CancellationQuote({
    required this.tier,
    required this.daysUntilCheckIn,
    required this.fee,
    required this.refund,
    required this.totalPrice,
  });

  bool get hasFee => fee > 0;

  String get headline {
    switch (tier) {
      case CancellationTier.free:
        return 'Free cancellation';
      case CancellationTier.partial:
        return '50% cancellation fee applies';
      case CancellationTier.none:
        return 'No refund available';
    }
  }

  String get explanation {
    switch (tier) {
      case CancellationTier.free:
        return "You're cancelling 15+ days before check-in, so this stay is fully refundable.";
      case CancellationTier.partial:
        return "You'll be charged 50% of the total as a cancellation fee, and refunded the rest.";
      case CancellationTier.none:
        return "You're cancelling on the day of check-in or the day before, so this booking is non-refundable.";
    }
  }
}
