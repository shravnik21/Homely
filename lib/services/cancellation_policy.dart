/// Homely's cancellation policies. Every listing has its own selected
/// policy (see the wizard's Cancellation Policy step) - one of three
/// tiers, same as Airbnb's own naming:
///   - moderate: the original app-wide sliding scale, unchanged, now
///     just one of three options instead of the only one. Used as the
///     DB default so every pre-existing listing behaves exactly as it
///     always did until its host actively picks something else.
///   - strict: a stricter, less refundable tier with its own fixed
///     thresholds, not host-customisable.
///   - flexible: the HOST defines their own refund terms - a single
///     cutoff ("free cancellation up to X days before check-in") plus
///     the fee that applies after that cutoff, right up to check-in.
///
/// A cancellation is priced at the moment it happens - once applied,
/// the fee/refund are stored on the booking row itself
/// (`cancellation_fee` / `refund_amount`) rather than recomputed
/// later, so the numbers a guest and host see stay stable even if a
/// listing's policy changes after the fact (see BookingService.cancelBooking).
class CancellationPolicy {
  const CancellationPolicy._();

  // ---- Moderate tier (unchanged from the original single policy) ----
  static const int moderateFullRefundThresholdDays = 15;
  static const int moderateNoRefundThresholdDays = 2;
  static const double moderatePartialRefundFeeRate = 0.5;

  // ---- Strict tier - mirrors Airbnb's own Strict policy: half back
  // if cancelled a week or more out, nothing back after that. ----
  static const int strictPartialRefundThresholdDays = 7;
  static const double strictPartialRefundFeeRate = 0.5;

  // ---- Flexible tier defaults - only used to pre-fill the wizard's
  // input fields the first time a host selects Flexible; every actual
  // Flexible listing stores its own chosen values on the place row. ----
  static const int flexibleDefaultFreeDays = 3;
  static const double flexibleDefaultFeePercent = 100;

  /// Whole calendar days between now and check-in. Negative once
  /// check-in has already passed.
  static int daysUntilCheckIn(DateTime checkIn) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkInDay = DateTime(checkIn.year, checkIn.month, checkIn.day);
    return checkInDay.difference(today).inDays;
  }

  /// Computes what cancelling right now would cost, for a booking
  /// worth [totalPrice] checking in on [checkIn], under [policyType].
  /// [flexibleFreeDays]/[flexibleFeePercent] are only read when
  /// [policyType] is [CancellationPolicyType.flexible] - falls back to
  /// the class-level defaults above if a Flexible listing somehow has
  /// neither set.
  static CancellationQuote quote({
    required CancellationPolicyType policyType,
    required DateTime checkIn,
    required num totalPrice,
    int? flexibleFreeDays,
    num? flexibleFeePercent,
  }) {
    final days = daysUntilCheckIn(checkIn);
    late final double feeRate;

    switch (policyType) {
      case CancellationPolicyType.moderate:
        if (days >= moderateFullRefundThresholdDays) {
          feeRate = 0.0;
        } else if (days >= moderateNoRefundThresholdDays) {
          feeRate = moderatePartialRefundFeeRate;
        } else {
          feeRate = 1.0;
        }
        break;
      case CancellationPolicyType.strict:
        feeRate = days >= strictPartialRefundThresholdDays
            ? strictPartialRefundFeeRate
            : 1.0;
        break;
      case CancellationPolicyType.flexible:
        final freeDays = flexibleFreeDays ?? flexibleDefaultFreeDays;
        final feePercent = flexibleFeePercent ?? flexibleDefaultFeePercent;
        feeRate = days >= freeDays ? 0.0 : (feePercent / 100).clamp(0, 1);
        break;
    }

    final fee = totalPrice * feeRate;
    final refund = totalPrice - fee;
    return CancellationQuote(
      daysUntilCheckIn: days,
      fee: fee,
      refund: refund,
      totalPrice: totalPrice,
    );
  }

  /// Plain-language tier breakdown for [policyType] - used by the
  /// wizard's policy cards and the guest-facing
  /// CancellationPolicyDetailScreen so both always describe exactly
  /// what [quote] would actually charge, with no hardcoded text to
  /// drift out of sync.
  static List<CancellationPolicyTierRow> describeTiers({
    required CancellationPolicyType policyType,
    int? flexibleFreeDays,
    num? flexibleFeePercent,
  }) {
    switch (policyType) {
      case CancellationPolicyType.moderate:
        final partialRefundPct =
            (100 - moderatePartialRefundFeeRate * 100).round();
        return [
          CancellationPolicyTierRow(
            rangeLabel:
                '$moderateFullRefundThresholdDays+ days before check-in',
            outcomeLabel: 'Free cancellation',
            good: true,
          ),
          CancellationPolicyTierRow(
            rangeLabel:
                '$moderateNoRefundThresholdDays–${moderateFullRefundThresholdDays - 1} days before check-in',
            outcomeLabel: '$partialRefundPct% refund',
            good: false,
          ),
          const CancellationPolicyTierRow(
            rangeLabel: 'Day before or day of check-in',
            outcomeLabel: 'No refund',
            good: false,
          ),
        ];
      case CancellationPolicyType.strict:
        final partialRefundPct = (strictPartialRefundFeeRate * 100).round();
        return [
          CancellationPolicyTierRow(
            rangeLabel:
                '$strictPartialRefundThresholdDays+ days before check-in',
            outcomeLabel: '$partialRefundPct% refund',
            good: false,
          ),
          CancellationPolicyTierRow(
            rangeLabel:
                'Less than $strictPartialRefundThresholdDays days before check-in',
            outcomeLabel: 'No refund',
            good: false,
          ),
        ];
      case CancellationPolicyType.flexible:
        final freeDays = flexibleFreeDays ?? flexibleDefaultFreeDays;
        final feePercent =
            (flexibleFeePercent ?? flexibleDefaultFeePercent).round();
        final refundPercent = 100 - feePercent;
        final dayWord = freeDays == 1 ? 'day' : 'days';
        return [
          CancellationPolicyTierRow(
            rangeLabel: '$freeDays+ $dayWord before check-in',
            outcomeLabel: 'Free cancellation',
            good: true,
          ),
          CancellationPolicyTierRow(
            rangeLabel: 'Less than $freeDays $dayWord before check-in',
            outcomeLabel:
                feePercent >= 100 ? 'No refund' : '$refundPercent% refund',
            good: false,
          ),
        ];
    }
  }

  /// One-line summary for [policyType] - used on the wizard's policy
  /// picker cards and the top of CancellationPolicyDetailScreen.
  static String summaryFor(
    CancellationPolicyType policyType, {
    int? flexibleFreeDays,
    num? flexibleFeePercent,
  }) {
    switch (policyType) {
      case CancellationPolicyType.moderate:
        return 'Full refund up to $moderateFullRefundThresholdDays days before '
            'check-in, ${(100 - moderatePartialRefundFeeRate * 100).round()}% '
            'refund down to $moderateNoRefundThresholdDays days out, then '
            'non-refundable.';
      case CancellationPolicyType.strict:
        return '${(strictPartialRefundFeeRate * 100).round()}% refund up to '
            '$strictPartialRefundThresholdDays days before check-in, then '
            'non-refundable.';
      case CancellationPolicyType.flexible:
        final freeDays = flexibleFreeDays ?? flexibleDefaultFreeDays;
        final feePercent =
            (flexibleFeePercent ?? flexibleDefaultFeePercent).round();
        final dayWord = freeDays == 1 ? 'day' : 'days';
        return 'Free cancellation up to $freeDays $dayWord before check-in'
            '${feePercent >= 100 ? ', non-refundable after that' : ', $feePercent% fee after that'} '
            '- set by the host.';
    }
  }
}

/// The three cancellation policies a host can pick for a listing -
/// mirrors the `cancellation_policy_type` check constraint in
/// schema_cancellation_policy_type.sql exactly.
enum CancellationPolicyType { flexible, moderate, strict }

extension CancellationPolicyTypeX on CancellationPolicyType {
  /// Parses the DB column's stored value, defaulting to Moderate for
  /// null/unrecognised values - same "moderate is the safe default"
  /// reasoning as the DB column's own default.
  static CancellationPolicyType fromDb(String? value) {
    switch (value) {
      case 'flexible':
        return CancellationPolicyType.flexible;
      case 'strict':
        return CancellationPolicyType.strict;
      case 'moderate':
      default:
        return CancellationPolicyType.moderate;
    }
  }

  String get dbValue => name;

  String get label {
    switch (this) {
      case CancellationPolicyType.flexible:
        return 'Flexible';
      case CancellationPolicyType.moderate:
        return 'Moderate';
      case CancellationPolicyType.strict:
        return 'Strict';
    }
  }
}

/// One row of a policy's tier breakdown - e.g. "15+ days before
/// check-in" -> "Free cancellation". [good] drives the row's icon
/// (checkmark vs dash) wherever it's rendered.
class CancellationPolicyTierRow {
  final String rangeLabel;
  final String outcomeLabel;
  final bool good;

  const CancellationPolicyTierRow({
    required this.rangeLabel,
    required this.outcomeLabel,
    required this.good,
  });
}

class CancellationQuote {
  final int daysUntilCheckIn;
  final num fee;
  final num refund;
  final num totalPrice;

  const CancellationQuote({
    required this.daysUntilCheckIn,
    required this.fee,
    required this.refund,
    required this.totalPrice,
  });

  bool get hasFee => fee > 0;

  /// Derived directly from the actual fee/refund numbers rather than
  /// a hardcoded per-tier switch, so this reads correctly for any
  /// policy type - including a host's own custom Flexible fee %,
  /// which no fixed set of tier labels could describe in advance.
  String get headline {
    if (fee <= 0) return 'Free cancellation';
    if (refund <= 0) return 'No refund available';
    final refundPct = (100 - (fee / totalPrice * 100)).round();
    return '$refundPct% refund available';
  }

  String get explanation {
    if (fee <= 0) {
      return "You're cancelling far enough ahead of check-in, so this stay is fully refundable.";
    }
    if (refund <= 0) {
      return "You're cancelling too close to check-in for a refund under this listing's policy.";
    }
    final feePct = (fee / totalPrice * 100).round();
    return "You'll be charged $feePct% of the total as a cancellation fee, and refunded the rest.";
  }
}
