/// Homely's payout policy - translates a booking's guest-facing
/// numbers into what the host actually earns from it.
///
/// HOW HOMELY MAKES MONEY:
/// Guests pay a flat 5% service fee on top of the nightly subtotal
/// at booking time (see `BookingScreen._serviceFee`). That fee is
/// guest-side only - Homely doesn't take a cut from the host - so a
/// host's payout for a completed stay is simply the nightly subtotal
/// (`pricePerNight x nights`), in full.
///
/// WHEN A PAYOUT IS RELEASED:
/// Funds are held until the guest has checked out, in case anything
/// needs resolving during the stay. Until then it's an "upcoming"
/// payout on the host's Earnings screen rather than "paid out".
///
/// CANCELLATIONS:
/// If a guest cancels close enough to check-in that
/// `CancellationPolicy` charges a fee, the host is compensated with
/// that fee - capped at what the stay would have paid out normally,
/// since a host is never compensated for more than the booking was
/// actually worth. A free cancellation (15+ days out) earns the host
/// nothing, since nobody was charged.
///
/// This is the single place both `HostBookingDetailScreen` (single
/// booking) and the Earnings screens (aggregated across every
/// booking) get these numbers from, so they can never disagree with
/// each other.
class PayoutPolicy {
  const PayoutPolicy._();

  static const double guestServiceFeeRate = 0.05; // 5%, guest-side only

  /// What the host earns for one stay - the nightly subtotal before
  /// Homely's guest-side service fee was added. Falls back to
  /// backing the subtotal out of [totalPrice] for the rare older
  /// booking that doesn't have a reliable `pricePerNight`/`nights`
  /// pair recorded on it.
  static num stayPayout({
    required num pricePerNight,
    required int nights,
    required num totalPrice,
  }) {
    final subtotal = pricePerNight * nights;
    if (subtotal > 0) return subtotal;
    return totalPrice / (1 + guestServiceFeeRate);
  }

  /// The guest-side service fee Homely collected for this stay -
  /// informational only, never deducted from the host's payout.
  static num guestServiceFeeFor({
    required num totalPrice,
    required num stayPayout,
  }) =>
      totalPrice - stayPayout;

  /// What the host is compensated when a guest's cancellation was
  /// charged [cancellationFee], for a stay that would otherwise have
  /// paid out [stayPayout].
  static num cancellationCompensation({
    required num cancellationFee,
    required num stayPayout,
  }) =>
      cancellationFee < stayPayout ? cancellationFee : stayPayout;
}
