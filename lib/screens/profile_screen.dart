import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/screens/auth/login_screen.dart';
import 'package:homely_app/screens/settings/settings_screen.dart';
import 'package:homely_app/screens/settings/about_screen.dart';
import 'package:homely_app/screens/my_bookings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();

  // full_name was stored as user metadata during signup
  // (see AuthService.signUp -> data: {'full_name': fullName}).
  String get _fullName {
    final meta = _authService.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return 'Guest';
    return name.trim();
  }

  String get _email => _authService.currentUser?.email ?? '—';

  String get _initial {
    final name = _fullName.trim();
    if (name.isEmpty || name == 'Guest') return 'G';
    return name[0].toUpperCase();
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(child: _buildAvatar()),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _fullName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                _email,
                style: const TextStyle(fontSize: 14, color: AppColors.grey),
              ),
            ),
            const SizedBox(height: 32),
            _buildMenuTile(
              icon: Icons.luggage_outlined,
              label: 'My Bookings',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildMenuTile(
              icon: Icons.settings_outlined,
              label: 'Account Settings',
              onTap: _openSettings,
            ),
            const SizedBox(height: 12),
            _buildMenuTile(
              icon: Icons.info_outline,
              label: 'About',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildMenuTile(
              icon: Icons.logout,
              label: 'Logout',
              iconColor: AppColors.error,
              labelColor: AppColors.error,
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = AppColors.dark,
    Color labelColor = AppColors.dark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
