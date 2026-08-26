import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';

/// One row of a cancellation-policy tier breakdown - a day range on
/// the left, the refund outcome on the right, with a check/dash icon
/// reflecting how good that outcome is. Originally lived as a private
/// widget inside BookingScreen; pulled out here so
/// CancellationPolicyDetailScreen can reuse the exact same look.
class PolicyRow extends StatelessWidget {
  final String days;
  final String outcome;
  final bool good;

  const PolicyRow({
    super.key,
    required this.days,
    required this.outcome,
    required this.good,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          good ? Icons.check_circle_outline : Icons.remove_circle_outline,
          size: 16,
          color: good ? Colors.green[700] : AppColors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            days,
            style: const TextStyle(fontSize: 12.5, color: AppColors.dark),
          ),
        ),
        Text(
          outcome,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: good ? Colors.green[700] : AppColors.dark,
          ),
        ),
      ],
    );
  }
}
