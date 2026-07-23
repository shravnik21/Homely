import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/screens/host/host_home_screen.dart';

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}

const _slides = [
  _OnboardingSlide(
    icon: Icons.home_work_outlined,
    title: 'List Your Property',
    description:
        'Add your farmhouse, villa, apartment or any space you have '
        'and turn it into a source of income.',
  ),
  _OnboardingSlide(
    icon: Icons.calendar_month_outlined,
    title: 'Manage Bookings',
    description:
        'Accept or decline requests, keep track of your calendar, and '
        'stay on top of every reservation in one place.',
  ),
  _OnboardingSlide(
    icon: Icons.insights_outlined,
    title: 'Track Your Earnings',
    description:
        'See how your listings are performing - views, bookings, and '
        'income - all from your Host Dashboard.',
  ),
];

/// Shown exactly once, right after a host's first successful sign-in
/// (see AuthService.hasCompletedHostOnboarding). Tapping "Get Started"
/// marks it complete in both auth metadata and the profiles table, so
/// it never appears again for this account.
class HostOnboardingScreen extends StatefulWidget {
  const HostOnboardingScreen({super.key});

  @override
  State<HostOnboardingScreen> createState() => _HostOnboardingScreenState();
}

class _HostOnboardingScreenState extends State<HostOnboardingScreen> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();

  int _currentPage = 0;
  bool _isFinishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isFinishing = true);
    try {
      await _authService.markHostOnboardingComplete();
    } catch (_) {
      // Even if the DB write fails, don't trap the host on this
      // screen - metadata is best-effort and the DB write can be
      // retried by simply reaching this screen once more if needed.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HostHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: _isFinishing ? null : _finishOnboarding,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: AppColors.grey, fontSize: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(slide.icon,
                              size: 64, color: AppColors.primary),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.grey,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isFinishing
                      ? null
                      : () {
                          if (isLastPage) {
                            _finishOnboarding();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                  child: _isFinishing
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(isLastPage ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
