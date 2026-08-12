import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';

/// Read-only row of stars for showing an average rating (place cards,
/// listing summaries, review list items). Renders full, half, and
/// empty stars from any double value (e.g. 4.3 -> 4 full + 1 half).
class StarRatingDisplay extends StatelessWidget {
  final double rating;
  final double size;
  final Color filledColor;
  final Color emptyColor;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 16,
    this.filledColor = AppColors.primary,
    this.emptyColor = AppColors.lightGrey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        IconData icon;
        if (rating >= starValue) {
          icon = Icons.star_rounded;
        } else if (rating >= starValue - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(
          icon,
          size: size,
          color: rating >= starValue - 0.5 ? filledColor : emptyColor,
        );
      }),
    );
  }
}

/// Interactive 1-5 star selector for [WriteReviewScreen] - tap a star
/// to jump straight to that rating, or drag across the row to slide
/// between them, same interaction Airbnb's own review composer uses.
class StarRatingInput extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 44,
  });

  void _updateFromLocalPosition(Offset localPosition, double totalWidth) {
    final starWidth = totalWidth / 5;
    var index = (localPosition.dx / starWidth).ceil();
    if (index < 1) index = 1;
    if (index > 5) index = 5;
    onChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = size * 5;
    return GestureDetector(
      onTapDown: (details) =>
          _updateFromLocalPosition(details.localPosition, totalWidth),
      onHorizontalDragUpdate: (details) =>
          _updateFromLocalPosition(details.localPosition, totalWidth),
      child: SizedBox(
        width: totalWidth,
        height: size,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final filled = index < rating;
            return Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: filled ? AppColors.primary : AppColors.lightGrey,
            );
          }),
        ),
      ),
    );
  }
}
