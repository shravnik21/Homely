import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/cancellation_policy.dart';
import 'package:homely_app/widgets/policy_row.dart';

/// Full detail of the cancellation policy a host picked for [place] -
/// opened by tapping the "Cancellation Policy" card on
/// PlaceDetailScreen, or the tappable warning on BookingScreen. Purely
/// a read-only explainer; the actual fee/refund a guest would get is
/// computed at cancel-time by CancellationPolicy.quote() using these
/// same stored values (see BookingDetailScreen._confirmCancel), so
/// what's shown here can never drift from what's actually charged.
class CancellationPolicyDetailScreen extends StatelessWidget {
  final Place place;

  const CancellationPolicyDetailScreen({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final type = CancellationPolicyTypeX.fromDb(place.cancellationPolicyType);
    final rows = CancellationPolicy.describeTiers(
      policyType: type,
      flexibleFreeDays: place.cancellationFlexibleFreeDays,
      flexibleFeePercent: place.cancellationFlexibleFeePercent,
    );

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        title: const Text('Cancellation Policy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${type.label} policy',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              place.title,
              style: const TextStyle(color: AppColors.grey, fontSize: 14),
            ),
            const SizedBox(height: 22),
            const Text(
              'What happens when you cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              CancellationPolicy.summaryFor(
                type,
                flexibleFreeDays: place.cancellationFlexibleFreeDays,
                flexibleFeePercent: place.cancellationFlexibleFeePercent,
              ),
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    PolicyRow(
                      days: rows[i].rangeLabel,
                      outcome: rows[i].outcomeLabel,
                      good: rows[i].good,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'The exact fee is calculated the moment you cancel, based on '
              'how many days remain before check-in - you always see the '
              'real amount before confirming a cancellation.',
              style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
