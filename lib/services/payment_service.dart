import 'package:supabase_flutter/supabase_flutter.dart';

/// What create-razorpay-order (the Edge Function) hands back - just
/// enough for Razorpay Checkout to open. amount is in paise, exactly
/// as Razorpay itself expects it.
class RazorpayOrder {
  final String orderId;
  final int amount;
  final String currency;
  final String keyId;

  const RazorpayOrder({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.keyId,
  });

  factory RazorpayOrder.fromMap(Map<String, dynamic> map) => RazorpayOrder(
        orderId: map['orderId'] as String,
        amount: map['amount'] as int,
        currency: map['currency'] as String,
        keyId: map['keyId'] as String,
      );
}

/// Talks to the create-razorpay-order Edge Function (see
/// supabase/functions/create-razorpay-order/index.ts) - the only
/// place that actually computes what a booking costs. BookingScreen
/// never sends a price to us or to Razorpay; it only sends WHAT is
/// being booked (place/dates/guests) and gets back HOW MUCH to
/// charge, computed server-side from the listing's real price.
class PaymentService {
  final _client = Supabase.instance.client;

  Future<RazorpayOrder> createOrder({
    required String placeId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
  }) async {
    final response = await _client.functions.invoke(
      'create-razorpay-order',
      body: {
        'placeId': placeId,
        'checkIn': _dateOnly(checkIn),
        'checkOut': _dateOnly(checkOut),
        'guests': guests,
      },
    );

    final data = response.data;
    if (response.status != 200) {
      final message =
          (data is Map && data['error'] is String) ? data['error'] as String : null;
      throw Exception(message ?? 'Could not start payment. Please try again.');
    }

    return RazorpayOrder.fromMap(data as Map<String, dynamic>);
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Step 2 of 2, called once Razorpay Checkout reports success.
  /// Sends the three values Checkout hands back - order id, payment
  /// id, and signature - to verify-and-create-booking, which
  /// recomputes the signature itself using RAZORPAY_KEY_SECRET (never
  /// on-device) and only creates the `bookings` row if it matches.
  ///
  /// This replaces the old flow where BookingScreen inserted the
  /// booking directly the moment Checkout's on-device callback fired
  /// - nothing could actually verify a real payment had happened at
  /// that point. Returns the new booking's id.
  Future<String> verifyAndCreateBooking({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final response = await _client.functions.invoke(
      'verify-and-create-booking',
      body: {
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      },
    );

    final data = response.data;
    if (response.status != 200) {
      final message =
          (data is Map && data['error'] is String) ? data['error'] as String : null;
      throw Exception(
        message ?? 'Payment could not be verified. Contact support if you were charged.',
      );
    }

    return (data as Map<String, dynamic>)['bookingId'] as String;
  }
}
