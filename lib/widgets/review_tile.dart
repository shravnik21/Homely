import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/review.dart';
import 'package:homely_app/widgets/star_rating.dart';

/// One review's display row - avatar initial, reviewer name, date,
/// star rating, and comment. Shared by [PlaceDetailScreen]'s guest-
/// facing reviews list and the host-facing listing reviews screen so
/// both read identically, matching Airbnb's own single review-list
/// format used in both places.
class ReviewTile extends StatelessWidget {
  final Review review;

  const ReviewTile({super.key, required this.review});

  String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary,
          child: Text(
            review.reviewerInitial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
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
                      review.reviewerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(review.createdAt),
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              StarRatingDisplay(rating: review.rating.toDouble(), size: 14),
              if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  review.comment!,
                  style: const TextStyle(fontSize: 13, color: AppColors.grey, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
