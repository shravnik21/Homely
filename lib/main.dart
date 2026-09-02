import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'utils/connectivity_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const HomelyApp());
}

class HomelyApp extends StatefulWidget {
  const HomelyApp({super.key});

  @override
  State<HomelyApp> createState() => _HomelyAppState();
}

class _HomelyAppState extends State<HomelyApp> {
  /// Lets the auth-state listener below push a screen from outside
  /// any widget's BuildContext - needed because the magic-link deep
  /// link can arrive at any time (app cold-started from the link,
  /// or already open in the background), not just while some
  /// specific screen happens to be on screen.
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    // supabase_flutter watches for the app being opened via the
    // custom URL scheme registered natively (Android's
    // AndroidManifest.xml intent-filter / iOS's Info.plist
    // CFBundleURLTypes) and, once it recognizes the incoming link as
    // a password-recovery link, exchanges it for a short-lived
    // "recovery" session and fires this event - no manual link
    // parsing needed on our end. This fires however the app was
    // opened, so it covers both "already running in the background"
    // and "cold start from tapping the email link".
    _authSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Homely',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
      // Watches connectivity for the whole app - the moment the
      // device has no network at all, this takes over with a plain
      // "check your internet connection" screen instead of letting
      // whatever's on screen fail with a raw backend error.
      builder: (context, child) =>
          ConnectivityGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
