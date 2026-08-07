import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/supabase_config.dart';

/// Wraps a single Supabase call with a couple of automatic retries
/// for a transient failure users can hit through no fault of their
/// own: the device's clock briefly disagreeing with the server right
/// after reconnecting from a no-network area
/// (`PostgrestException` code `PGRST303`, "JWT issued at future").
/// The OS usually finishes its NTP sync within a second or two, so a
/// short delay plus a forced session refresh is normally enough to
/// fix it without the user having to do anything.
///
/// Not a replacement for [AutoReloadOnReconnectMixin] in
/// `auto_reload_on_reconnect.dart` - that one covers "this screen
/// already gave up, reload it once we're back online"; this one
/// covers "retry this one call a couple of times, right now, before
/// giving up on it".
///
/// Usage:
/// ```dart
/// _placesFuture = withRetry(() => _placesService.getPlaces());
/// ```
Future<T> withRetry<T>(
  Future<T> Function() action, {
  int retries = 2,
  Duration delay = const Duration(seconds: 2),
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await action();
    } catch (e) {
      attempt++;
      final isClockSkewIssue = e is PostgrestException && e.code == 'PGRST303';
      if (attempt > retries || !isClockSkewIssue) rethrow;

      // Give the device's clock a moment to finish syncing, then
      // force a fresh session/token before trying again - reusing
      // the old (still "future-dated") token would just fail the
      // exact same way immediately.
      await Future.delayed(delay);
      try {
        await SupabaseConfig.client.auth.refreshSession();
      } catch (_) {
        // If refreshing the session itself fails, let the next loop
        // iteration's plain retry surface the real error instead of
        // masking it with this one.
      }
    }
  }
}
