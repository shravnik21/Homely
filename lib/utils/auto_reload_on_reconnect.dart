import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Mix into any `State` that fetches data on load (a `FutureBuilder`
/// screen, a dashboard, etc) to have it automatically refetch the
/// moment the device regains a network connection - instead of
/// leaving the user stuck on an error screen until they notice and
/// manually pull-to-refresh.
///
/// Covers exactly the cases discussed on the host dashboard work:
/// the user was in a no-network area, or the very first request
/// after reconnecting failed because the device's clock hadn't
/// finished syncing yet (the `PGRST303 "JWT issued at future"`
/// error) - both show up as "the app loaded once, then failed, then
/// nothing happens until the user does something about it" unless a
/// screen explicitly listens for reconnection like this.
///
/// Usage:
/// ```dart
/// class _HomeScreenState extends State<HomeScreen>
///     with AutoReloadOnReconnectMixin {
///   @override
///   void initState() {
///     super.initState();
///     _loadPlaces();
///     startAutoReloadOnReconnect();
///   }
///
///   @override
///   void dispose() {
///     disposeAutoReloadOnReconnect();
///     super.dispose();
///   }
///
///   @override
///   void onReconnected() => _loadPlaces();
/// }
/// ```
mixin AutoReloadOnReconnectMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Assume connected until we hear otherwise, so we don't fire a
  // spurious "reconnected" reload on the very first event we get.
  bool _hasConnection = true;

  /// Called whenever connectivity flips from "none" to "has a
  /// connection" while this screen is alive. Implement this the same
  /// way as the screen's normal manual-refresh method - re-kick off
  /// whatever Future(s)/setState calls load its data.
  void onReconnected();

  /// Call from `initState()`.
  void startAutoReloadOnReconnect() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final isConnected = results.any((r) => r != ConnectivityResult.none);

    if (isConnected && !_hasConnection) {
      // Just came back online after being offline. A freshly
      // reconnected device's clock can take a moment to finish
      // syncing via NTP - retrying instantly can still hit the same
      // "JWT issued at future" error, so give it a short beat before
      // reloading rather than firing immediately.
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) onReconnected();
      });
    }

    _hasConnection = isConnected;
  }

  /// Call from `dispose()`.
  void disposeAutoReloadOnReconnect() {
    _connectivitySub?.cancel();
  }
}
