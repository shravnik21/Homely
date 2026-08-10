import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/widgets/primary_button.dart';

/// The full-screen takeover shown whenever the device has no network
/// connection at all - modelled on the plain, centered "you're
/// offline" screens apps like Airbnb show instead of letting a raw
/// backend/network error leak through to the user.
///
/// Kept deliberately blank/quiet (no illustration, no app chrome) so
/// it reads as "the app noticed you're offline", not as another
/// error state to interpret.
class NoInternetScreen extends StatelessWidget {
  final VoidCallback? onRetry;
  final bool isRetrying;

  const NoInternetScreen({super.key, this.onRetry, this.isRetrying = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: AppColors.lightGrey,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: AppColors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'No Internet Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Please check your internet connection and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.grey, height: 1.4),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 180,
                    child: PrimaryButton(
                      text: 'Try Again',
                      isLoading: isRetrying,
                      onPressed: onRetry,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
