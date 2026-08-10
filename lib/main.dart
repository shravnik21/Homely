import 'package:flutter/material.dart';
import 'config/supabase_config.dart';
import 'config/app_theme.dart';
import 'screens/splash_screen.dart';
import 'utils/connectivity_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const HomelyApp());
}

class HomelyApp extends StatelessWidget {
  const HomelyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
