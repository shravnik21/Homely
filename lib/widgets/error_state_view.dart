import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/utils/network_error_helper.dart';

/// Drop-in replacement for the old `Text('Could not load X.\n$error')`
/// pattern that was scattered across every `FutureBuilder`'s
/// `snapshot.hasError` branch - it showed the raw exception (a
/// `PostgrestException`, a `SocketException`...) straight to the
/// user. This shows a clean, consistent message instead (via
/// [friendlyError]), with an icon and an optional retry button.
///
/// Usage:
/// ```dart
/// if (snapshot.hasError) {
///   return ErrorStateView(
///     error: snapshot.error!,
///     fallbackMessage: 'Could not load your bookings.',
///     onRetry: _refresh,
///   );
/// }
/// ```
class ErrorStateView extends StatelessWidget {
  final Object error;
  final String fallbackMessage;
  final VoidCallback? onRetry;

  const ErrorStateView({
    super.key,
    required this.error,
    this.fallbackMessage = 'Something went wrong. Please try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isOffline = isNetworkError(error);
    final message = friendlyError(error, fallback: fallbackMessage);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 40,
              color: AppColors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
