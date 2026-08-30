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
}
