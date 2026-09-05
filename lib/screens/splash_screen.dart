import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/screens/auth/login_screen.dart';
import 'package:homely_app/screens/guest/guest_root_screen.dart';
import 'package:homely_app/screens/host/host_root_screen.dart';
import 'package:homely_app/screens/host/host_onboarding_screen.dart';

// Minimal splash, back on-brand: solid red (AppColors.primary)
// background with a subtle depth gradient, rather than the
// near-black version this replaces. Since the icon is itself a red
// square, everything around it (glow, ring, progress bar) uses white
// accents instead of red-on-red so it doesn't disappear into the
// background.
const _deepRed = Color(0xFFB8203C); // a shade darker than AppColors.primary

const _title = 'HOMELY';
const _tagline = 'FARMHOUSES  •  VILLAS  •  FLATS  •  APARTMENTS';
const _loadingCaption = 'FINDING YOUR NEXT STAY';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();

  // Plays once - icon, title, tagline, and the progress bar fading/
  // sliding in, in sequence.
  late final AnimationController _entrance;

  // Repeats, reversing - the icon's soft glow breathing.
  late final AnimationController _pulse;

  // Repeats, NOT reversing - the highlight sliding along the
  // progress track, reset to the start each lap like a typical
  // indeterminate loading bar.
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    _navigateNext();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _navigateNext() async {
    // Longer than before (was 2.4s) - gives the entrance animation
    // room to fully settle plus a proper beat to actually look at
    // the finished screen, rather than cutting away right as it
    // lands.
    await Future.delayed(const Duration(milliseconds: 3300));
    if (!mounted) return;

    final loggedIn = _authService.isLoggedIn;
    final isHost = _authService.currentUserRole == 'host';
    final needsOnboarding =
        loggedIn && isHost && !_authService.hasCompletedHostOnboarding;

    final next = !loggedIn
        ? const LoginScreen()
        : needsOnboarding
            ? const HostOnboardingScreen()
            : isHost
                ? const HostRootScreen()
                : const GuestRootScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, _deepRed],
          ),
        ),
        child: Stack(
          children: [
            // A single faint white ring tucked in each far corner -
            // a quiet geometric accent, same idea as before, just
            // recoloured for the red background.
            Positioned(
              top: -90,
              right: -90,
              child: _ring(size: 260, opacity: 0.08),
            ),
            Positioned(
              bottom: -70,
              left: -70,
              child: _ring(size: 200, opacity: 0.06),
            ),
            Center(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _ring({required double size, required double opacity}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(opacity), width: 1),
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _animatedLogo(),
        const SizedBox(height: 26),
        _fadeSlide(
          interval: const Interval(0.2, 0.6, curve: Curves.easeOut),
          offset: 12,
          child: const Text(
            _title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _fadeSlide(
          interval: const Interval(0.4, 0.75, curve: Curves.easeOut),
          offset: 10,
          child: const Text(
            _tagline,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 76),
        _fadeSlide(
          interval: const Interval(0.65, 1.0, curve: Curves.easeOut),
          offset: 8,
          child: Column(
            children: [
              _progressBar(),
              const SizedBox(height: 14),
              const Text(
                _loadingCaption,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _animatedLogo() {
    final entranceCurve = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _pulse]),
      builder: (context, child) {
        final glowOpacity = 0.28 + 0.18 * _pulse.value;
        return Opacity(
          opacity: entranceCurve.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + 0.3 * entranceCurve.value,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // White glow, not red-on-red, so it actually reads
                // as a glow against the red background instead of
                // disappearing into it.
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(glowOpacity),
                    blurRadius: 46,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          // A thin white ring around the icon itself - the icon is a
          // red square, so without this it would blend straight into
          // an all-red background instead of reading as a badge.
          border: Border.all(color: Colors.white.withOpacity(0.55), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22.5),
          child: Image.asset(
            'assets/images/app_icon.png',
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _fadeSlide({
    required Interval interval,
    required double offset,
    required Widget child,
  }) {
    final animation = CurvedAnimation(parent: _entrance, curve: interval);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, (1 - animation.value) * offset),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _progressBar() {
    const trackWidth = 130.0;
    const trackHeight = 3.0;
    const highlightWidth = 40.0;

    return SizedBox(
      width: trackWidth,
      height: trackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: trackWidth,
            height: trackHeight,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(trackHeight / 2),
            ),
          ),
          AnimatedBuilder(
            animation: _progress,
            builder: (context, _) {
              final left = (trackWidth + highlightWidth) * _progress.value -
                  highlightWidth;
              return Positioned(
                left: left,
                child: Container(
                  width: highlightWidth,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    // White highlight against the translucent-white
                    // track - a red highlight here would read as
                    // muddy against an all-red page.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
