import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'help_support_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

/// Moved out of SettingsScreen into its own screen, reachable directly
/// from Profile - keeps Settings focused on account/preferences, and
/// gives "About" its own dedicated space alongside it.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'About',
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
            _menuTile(
              context,
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _menuTile(
              context,
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _menuTile(
              context,
              icon: Icons.help_outline,
              label: 'Help & Support',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _menuTile(
              context,
              icon: Icons.info_outline,
              label: 'App Version',
              trailingText: '1.3.0',
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    String? trailingText,
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
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  trailingText,
                  style: const TextStyle(color: AppColors.grey, fontSize: 13),
                ),
              ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
