import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/screens/auth/login_screen.dart';
import 'package:homely_app/screens/guest/guest_root_screen.dart';
import 'package:homely_app/screens/host/host_root_screen.dart';
import 'package:homely_app/screens/host/host_onboarding_screen.dart';

// White base (kept from the previous minimal pass) with the red
// decorative language from the Aurix reference layered back in - a
// soft glow breathing behind the icon, two faint rings in the
// corners, and a slim sliding progress bar - all re-tinted in the
// brand red instead of Aurix's orange, and all restrained enough
// (low opacity, slow motion) to sit quietly on white rather than
// fight it. Typography stays plain dark/grey, not the loud all-caps
// treatment - keeps this closer to "white minimal with red accents"
// than a full reskin back to the dark version.
const _title = 'Homely';
const _tagline = 'Farmhouses • Villas • Flats • Apartments';
const _loadingCaption = 'Finding your next stay';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();

  // Plays once - icon, title, tagline, progress bar fading/sliding
  // in, in sequence.
  late final AnimationController _entrance;

  // Repeats, reversing - the glow behind the icon breathing gently.
  late final AnimationController _pulse;

  // Repeats, NOT reversing - the highlight sliding along the
  // progress track.
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
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
        transitionDuration: const Duration(milliseconds: 450),
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
      backgroundColor: AppColors.white,
      body: Stack(
        children: [
          // Two faint red rings tucked in the far corners - the same
          // quiet geometric accent the dark version had, just tinted
          // for white instead of a dark background.
          Positioned(
            top: -90,
            right: -90,
            child: _ring(size: 260, opacity: 0.07),
          ),
          Positioned(
            bottom: -70,
            left: -70,
            child: _ring(size: 200, opacity: 0.06),
          ),
          Center(child: _content()),
        ],
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
          border: Border.all(color: AppColors.primary.withOpacity(opacity), width: 1),
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _animatedLogo(),
        const SizedBox(height: 24),
        _fadeSlide(
          interval: const Interval(0.25, 0.75, curve: Curves.easeOut),
          offset: 8,
          child: const Text(
            _title,
            style: TextStyle(
              color: AppColors.dark,
              fontSize: 27,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _fadeSlide(
          interval: const Interval(0.4, 0.9, curve: Curves.easeOut),
          offset: 6,
          child: const Text(
            _tagline,
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 60),
        _fadeSlide(
          interval: const Interval(0.6, 1.0, curve: Curves.easeOut),
          offset: 6,
          child: Column(
            children: [
              _progressBar(),
              const SizedBox(height: 12),
              const Text(
                _loadingCaption,
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _pulse]),
      builder: (context, child) {
        // Soft red glow behind the icon, breathing gently - the
        // Aurix touch, re-tinted for a white background where a
        // colored glow reads as a highlight rather than needing to
        // fight for contrast the way it did on the all-red version.
        final glowOpacity = 0.16 + 0.10 * _pulse.value;
        return Opacity(
          opacity: entranceCurve.value,
          child: Transform.scale(
            scale: 0.94 + 0.06 * entranceCurve.value,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(glowOpacity),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'assets/images/app_icon.png',
          width: 84,
          height: 84,
          fit: BoxFit.cover,
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
              color: AppColors.lightGrey,
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
                    color: AppColors.primary,
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
