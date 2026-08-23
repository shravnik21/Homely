import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';

/// One row from `notifications` (schema_notifications.sql). Named
/// `AppNotification` rather than `Notification` since the latter
/// collides with Flutter's own widget-tree notification system.
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? bookingId;
  final String? placeId;
  final int? milestoneDays;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.bookingId,
    this.placeId,
    this.milestoneDays,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      bookingId: map['booking_id'] as String?,
      placeId: map['place_id'] as String?,
      milestoneDays: map['milestone_days'] as int?,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Icon + tint per notification type, used by NotificationsScreen so
  /// each row is scannable at a glance without reading the body text.
  IconData get icon {
    switch (type) {
      case 'booking_confirmed':
        return Icons.check_circle_rounded;
      case 'booking_cancelled':
        return Icons.cancel_rounded;
      case 'booking_rescheduled':
        return Icons.event_repeat_rounded;
      case 'checkin_reminder':
        return Icons.luggage_rounded;
      case 'checkin_log_reminder':
        return Icons.how_to_reg_rounded;
      case 'review_prompt':
        return Icons.star_rounded;
      case 'new_message':
        return Icons.chat_bubble_rounded;
      case 'suggestion':
      default:
        return Icons.lightbulb_rounded;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'booking_confirmed':
        return const Color(0xFF2E7D32);
      case 'booking_cancelled':
        return AppColors.error;
      case 'booking_rescheduled':
        return const Color(0xFFB8860B);
      case 'checkin_reminder':
        return AppColors.primary;
      case 'checkin_log_reminder':
        return const Color(0xFF2E7D32);
      case 'review_prompt':
        return const Color(0xFFB8860B);
      case 'new_message':
        return AppColors.primary;
      case 'suggestion':
      default:
        return AppColors.grey;
    }
  }
}
