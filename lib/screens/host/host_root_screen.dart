import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/host_notifications_service.dart';
import 'host_home_screen.dart';
import 'host_bookings_screen.dart';
import 'host_calendar_screen.dart';
import 'host_notifications_screen.dart';
import 'host_profile_screen.dart';

/// The host side's root shell - mirrors [GuestRootScreen] exactly
/// (same floating pill nav bar, same IndexedStack-of-tabs approach),
/// just with the five destinations a host needs instead of a guest's
/// four: Home / Bookings / Calendar / Notifications / Profile. This
/// is what login/splash/host-onboarding now send a host to, in place
/// of the old bare `HostHomeScreen()`.
///
/// Each tab stays alive in the [IndexedStack] rather than rebuilding
/// on every switch, so e.g. the dashboard's scroll position or the
/// calendar's currently-viewed month survive a trip out to another
/// tab and back.
class HostRootScreen extends StatefulWidget {
  const HostRootScreen({super.key});

  @override
  State<HostRootScreen> createState() => _HostRootScreenState();
}

class _HostRootScreenState extends State<HostRootScreen> {
  static const _notificationsTabIndex = 3;

  final HostNotificationsService _notificationsService = HostNotificationsService();
  int _currentIndex = 0;
  int _unreadNotifications = 0;

  final List<Widget> _tabs = const [
    HostHomeScreen(),
    HostBookingsScreen(),
    HostCalendarScreen(),
    HostNotificationsScreen(),
    HostProfileScreen(),
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
    // itself, so re-check the count right as the host steps away
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

/// Same widget as GuestRootScreen's private `_FloatingNavBar`, just
/// duplicated here with the host's five items instead of four -
/// kept as a private copy per shell (rather than a shared exported
/// widget) since the two never need to vary independently, and a
/// shared widget would need its item list/badge index parameterised
/// for no real benefit today.
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
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.event_note_outlined, Icons.event_note_rounded, 'Bookings'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Calendar'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, 'Notifications'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  // Which index in _items gets the unread-count dot.
  static const _notificationsIndex = 3;

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
                        if (index == _notificationsIndex && unreadNotifications > 0)
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
