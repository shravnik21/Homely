import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:homely_app/widgets/no_internet_screen.dart';

/// Wraps the whole app (see `main.dart`'s `MaterialApp.builder`) and
/// watches the device's connectivity for as long as the app is
/// running. The moment there's no connection at all - airplane mode,
/// wifi/data off, no signal - this takes over the screen with
/// [NoInternetScreen] instead of letting whatever screen is
/// underneath fail and surface a raw Supabase/Postgres error.
///
/// The real screen is kept in the tree underneath (not replaced), so
/// nothing loses its state - the moment connectivity comes back, the
/// overlay just disappears and the user is exactly where they left
/// off. This is the single place that needs to exist for the "tried
/// to log in with no internet and got a database error" case: the
/// login screen never even gets a chance to make that failing
/// request, because this is already covering it.
class ConnectivityGate extends StatefulWidget {
  final Widget child;

  const ConnectivityGate({super.key, required this.child});

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> {
  static const _offlineDebounceDuration = Duration(seconds: 2);

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _offlineDebounceTimer;

  bool _isOffline = false;
  // Starts true so the very first check (kicked off from initState,
  // before the first build) doesn't need an extra setState() call to
  // show the "Try Again" button in a loading state.
  bool _isRetrying = true;

  @override
  void initState() {
    super.initState();
    _runCheck();
    _sub = _connectivity.onConnectivityChanged.listen(_handleResults);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _offlineDebounceTimer?.cancel();
    super.dispose();
  }

  // Brief wifi<->cellular handovers are routine on mobile and
  // normally resolve in under a second - reporting "offline"
  // instantly on every one of those would flash the takeover screen
  // for no reason. Coming back online is applied immediately (no
  // reason to make someone wait to get their app back), but going
  // offline only takes effect if the device is still disconnected
  // after a short debounce window.
  void _handleResults(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    _offlineDebounceTimer?.cancel();

    if (!offline) {
      if (mounted) setState(() => _isOffline = false);
      return;
    }

    _offlineDebounceTimer = Timer(_offlineDebounceDuration, () {
      if (mounted) setState(() => _isOffline = true);
    });
  }

  Future<void> _runCheck() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final offline = results.every((r) => r == ConnectivityResult.none);
      // No debounce here - this only ever runs at app launch or from
      // an explicit "Try Again" tap, both of which are the user (or
      // the app) deliberately asking "right now, are we online?", so
      // the answer should apply immediately either way.
      if (mounted) setState(() => _isOffline = offline);
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  /// Bound to the "Try Again" button - unlike the initial check, this
  /// runs well after the first build, so it's safe to flip
  /// [_isRetrying] back on immediately for the button's own spinner.
  Future<void> _retry() async {
    setState(() => _isRetrying = true);
    await _runCheck();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isOffline)
          Positioned.fill(
            child: NoInternetScreen(onRetry: _retry, isRetrying: _isRetrying),
          ),
      ],
    );
  }
}
