import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/screens/host/host_home_screen.dart';

enum _SlideType { single, steps }

class _OnboardingSlide {
  final _SlideType type;
  final IconData icon;
  final String title;
  final String? description;
  final List<String>? steps;

  const _OnboardingSlide.single({
    required this.icon,
    required this.title,
    required this.description,
  })  : type = _SlideType.single,
        steps = null;

  const _OnboardingSlide.steps({
    required this.icon,
    required this.title,
    required this.steps,
  })  : type = _SlideType.steps,
        description = null;
}

const _slides = [
  _OnboardingSlide.single(
    icon: Icons.home_work_outlined,
    title: 'List Your Property',
    description:
        'Add your farmhouse, villa, apartment or any space you have '
        'and turn it into a source of income.',
  ),
  _OnboardingSlide.steps(
    icon: Icons.checklist_outlined,
    title: "Here's How Hosting Works",
    steps: [
      'Create your listing - add photos, price and details',
      'Verify your identity - builds trust with guests',
      'Set up payouts - tell us where earnings should go',
      'Start hosting - accept bookings and welcome guests',
    ],
  ),
  _OnboardingSlide.single(
    icon: Icons.verified_user_outlined,
    title: 'Verify Your Identity',
    description:
        'Confirm your phone number and optionally upload a government '
        'ID. Verified hosts get more bookings because guests trust '
        'them more. You can do this anytime from your Host Profile.',
  ),
  _OnboardingSlide.single(
    icon: Icons.account_balance_outlined,
    title: 'Set Up Payouts',
    description:
        'Add your bank or UPI details so your earnings have somewhere '
        'to go. This is running in test mode for now, no real money '
        'moves - you can set it up anytime from your Host Profile.',
  ),
  _OnboardingSlide.single(
    icon: Icons.calendar_month_outlined,
    title: 'Manage Bookings',
    description:
        'Accept or decline requests, keep track of your calendar, and '
        'stay on top of every reservation in one place.',
  ),
  _OnboardingSlide.single(
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
                  return slide.type == _SlideType.steps
                      ? _buildStepsSlide(slide)
                      : _buildSingleSlide(slide);
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

  Widget _buildSingleSlide(_OnboardingSlide slide) {
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
            child: Icon(slide.icon, size: 64, color: AppColors.primary),
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
            slide.description ?? '',
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
  }

  // A distinct layout (numbered checklist instead of icon+paragraph)
  // used just for the "how hosting works" overview slide - gives the
  // guide/steps feel the rest of the carousel doesn't need.
  Widget _buildStepsSlide(_OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(slide.icon, size: 52, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(slide.steps!.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        slide.steps![i],
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.dark,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
