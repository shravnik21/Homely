import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();

  // UI-only for now - doesn't persist anywhere or actually change
  // app behaviour yet. Wiring it up (e.g. saving to profiles) is a
  // later phase.
  bool _pushNotifications = true;

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }

  Future<void> _changePassword() async {
    final email = _authService.currentUser?.email;
    if (email == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change Password'),
        content: Text(
          'We\'ll send a password reset link to $email. Continue?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // AuthService.resetPassword was built back in Phase 1 but never
      // actually used in the UI until now.
      await _authService.resetPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset link sent to $email')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send reset link: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
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
          'Settings',
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _sectionLabel('Account'),
            _menuTile(
              icon: Icons.person_outline,
              label: 'Edit Profile',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _menuTile(
              icon: Icons.lock_outline,
              label: 'Change Password',
              onTap: _changePassword,
            ),

            const SizedBox(height: 28),
            _sectionLabel('Preferences'),
            _switchTile(
              icon: Icons.notifications_outlined,
              label: 'Push Notifications',
              value: _pushNotifications,
              onChanged: (v) => setState(() => _pushNotifications = v),
            ),
            const SizedBox(height: 10),
            _menuTile(
              icon: Icons.language_outlined,
              label: 'Language',
              trailingText: 'English',
              onTap: () => _comingSoon('Language selection'),
            ),
            const SizedBox(height: 10),
            _menuTile(
              icon: Icons.currency_rupee_outlined,
              label: 'Currency',
              trailingText: 'INR (₹)',
              onTap: () => _comingSoon('Currency selection'),
            ),

            const SizedBox(height: 28),
            _sectionLabel('About'),
            _menuTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              onTap: () => _comingSoon('Privacy Policy'),
            ),
            const SizedBox(height: 10),
            _menuTile(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () => _comingSoon('Terms of Service'),
            ),
            const SizedBox(height: 10),
            _menuTile(
              icon: Icons.help_outline,
              label: 'Help & Support',
              onTap: () => _comingSoon('Help & Support'),
            ),
            const SizedBox(height: 10),
            _menuTile(
              icon: Icons.info_outline,
              label: 'App Version',
              trailingText: '1.0.0',
              onTap: null,
            ),

            const SizedBox(height: 28),
            _menuTile(
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.grey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    String? trailingText,
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
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  trailingText,
                  style: const TextStyle(color: AppColors.grey, fontSize: 13),
                ),
              ),
            if (onTap != null)
              const Icon(Icons.chevron_right,
                  color: AppColors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.dark, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.dark,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
