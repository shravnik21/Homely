import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/screens/auth/login_screen.dart';
import 'package:homely_app/screens/guest/guest_root_screen.dart';
import 'package:homely_app/screens/host/host_root_screen.dart';
import 'package:homely_app/screens/host/host_onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final loggedIn = _authService.isLoggedIn;
    final isHost = _authService.currentUserRole == 'host';
    final needsOnboarding =
        loggedIn && isHost && !_authService.hasCompletedHostOnboarding;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => !loggedIn
            ? const LoginScreen()
            : needsOnboarding
                ? const HostOnboardingScreen()
                : isHost
                    ? const HostRootScreen()
                    : const GuestRootScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Homely',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Farmhouses • Villas • Flats • Apartments',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
