import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/notifications_service.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';

/// The guest side's root shell - everything a logged-in guest sees is
/// one of four tabs here (Explore / Notifications / Trips / Profile),
/// switched via the floating bottom nav bar instead of each being its
/// own pushed route. This is what login/signup/splash now send a
/// guest to, in place of the old bare `HomeScreen()`.
///
/// Each tab is kept alive in an [IndexedStack] rather than rebuilt on
/// every switch, so e.g. Explore's search text and scroll position
/// survive a trip out to Trips and back.
///
/// Wishlist deliberately has no tab here - it stays reachable only
/// from the heart icon on Explore's own header, exactly as before.
class GuestRootScreen extends StatefulWidget {
  const GuestRootScreen({super.key});

  @override
  State<GuestRootScreen> createState() => _GuestRootScreenState();
}

class _GuestRootScreenState extends State<GuestRootScreen> {
  static const _notificationsTabIndex = 1;

  final NotificationsService _notificationsService = NotificationsService();
  int _currentIndex = 0;
  int _unreadNotifications = 0;

  final List<Widget> _tabs = const [
    HomeScreen(),
    NotificationsScreen(),
    MyBookingsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _notificationsService.getUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotifications = count);
    } catch (_) {
      // Non-critical - the badge just won't show a count this time.
    }
  }

  void _selectTab(int index) {
    final leavingNotifications = _currentIndex == _notificationsTabIndex;
    setState(() => _currentIndex = index);
    // Reading/marking-read only happens inside the Notifications tab
    // itself, so re-check the count right as the guest steps away
    // from it - that's the one moment the badge could be stale.
    if (leavingNotifications) _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        unreadNotifications: _unreadNotifications,
        onTap: _selectTab,
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final int unreadNotifications;
  final ValueChanged<int> onTap;

  const _FloatingNavBar({
    required this.currentIndex,
    required this.unreadNotifications,
    required this.onTap,
  });

  static const _items = [
    (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, 'Notifications'),
    (Icons.card_travel_outlined, Icons.card_travel_rounded, 'Trips'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(33),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (index) {
            final (outlineIcon, filledIcon, label) = _items[index];
            final isSelected = index == currentIndex;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(33),
                onTap: () => onTap(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          isSelected ? filledIcon : outlineIcon,
                          color: AppColors.primary,
                          size: 25,
                        ),
                        if (index == 1 && unreadNotifications > 0)
                          Positioned(
                            top: -3,
                            right: -5,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.white, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 150),
                      child: isSelected
                          ? Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
