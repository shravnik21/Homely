import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/services/host_service.dart';
import 'package:homely_app/screens/auth/login_screen.dart';
import 'package:homely_app/screens/host/host_verify_identity_screen.dart';
import 'package:homely_app/screens/host/host_payout_details_screen.dart';
import 'package:homely_app/screens/host/host_agreement_screen.dart';
import 'package:homely_app/screens/guest/settings/edit_profile_screen.dart';

/// Profile screen for hosts - mirrors the guest ProfileScreen's look
/// (avatar, name, email) but adds the host-specific setup steps:
/// identity verification, payout details, and agreement acceptance.
class HostProfileScreen extends StatefulWidget {
  const HostProfileScreen({super.key});

  @override
  State<HostProfileScreen> createState() => _HostProfileScreenState();
}

class _HostProfileScreenState extends State<HostProfileScreen> {
  final AuthService _authService = AuthService();
  final HostService _hostService = HostService();

  Map<String, dynamic>? _status;
  bool _isLoadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      // ONE query gets both the host setup status AND the live
      // name/email/phone from `profiles`, via the FK-based nested
      // select (schema_host_profiles_fk.sql). Since this is a live
      // reference, not a copy, any change made in Edit Profile shows
      // up here immediately on next load - no sync code needed.
      final status = await _hostService.getMyHostProfileWithAccountInfo();
      if (mounted) setState(() => _status = status);
    } finally {
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  Map<String, dynamic>? get _profileInfo =>
      _status?['profiles'] as Map<String, dynamic>?;

  String get _fullName {
    // host_profiles now has its OWN full_name column (duplicated,
    // kept in sync by AuthService.updateProfile()) - prefer that
    // directly over the joined `profiles` data. Metadata is only a
    // fallback for the very first frame before the query resolves.
    final name = _status?['full_name'] as String? ??
        _profileInfo?['full_name'] as String? ??
        _authService.currentUser?.userMetadata?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return 'Host';
    return name.trim();
  }

  String get _email =>
      _status?['email'] as String? ??
      _profileInfo?['email'] as String? ??
      _authService.currentUser?.email ??
      '—';

  // Phone isn't duplicated onto host_profiles (only full_name/email
  // are) - this still comes from the joined `profiles` data.
  String? get _phone => _profileInfo?['phone'] as String?;

  // True if any of the three mandatory setup steps is still
  // incomplete - same logic as HostService.hasIncompleteSetup(), but
  // computed locally from the already-loaded _status to avoid a
  // second network call.
  bool get _isSetupIncomplete {
    if (_status == null) return true;
    final verified = _status?['id_verification_status'] == 'verified' ||
        _status?['phone_verified'] == true;
    final payoutDone = _status?['payout_setup_complete'] == true;
    final agreementDone = _status?['host_agreement_accepted'] == true;
    return !(verified && payoutDone && agreementDone);
  }

  String get _initial {
    final name = _fullName.trim();
    if (name.isEmpty || name == 'Host') return 'H';
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

  // ---- Derived status labels ----

  String get _verificationLabel {
    final status = _status?['id_verification_status'] as String? ?? 'not_started';
    final phoneVerified = _status?['phone_verified'] as bool? ?? false;
    if (status == 'verified') return 'Verified';
    if (status == 'pending') return 'ID pending review';
    if (phoneVerified) return 'Phone verified';
    return 'Not started';
  }

  Color get _verificationColor {
    final status = _status?['id_verification_status'] as String? ?? 'not_started';
    final phoneVerified = _status?['phone_verified'] as bool? ?? false;
    if (status == 'verified') return Colors.green;
    if (status == 'pending') return Colors.orange;
    if (phoneVerified) return Colors.orange;
    return AppColors.grey;
  }

  String get _payoutLabel =>
      (_status?['payout_setup_complete'] as bool? ?? false)
          ? 'Set up'
          : 'Not set up';

  Color get _payoutColor =>
      (_status?['payout_setup_complete'] as bool? ?? false)
          ? Colors.green
          : AppColors.grey;

  String get _agreementLabel =>
      (_status?['host_agreement_accepted'] as bool? ?? false)
          ? 'Accepted'
          : 'Not accepted';

  Color get _agreementColor =>
      (_status?['host_agreement_accepted'] as bool? ?? false)
          ? Colors.green
          : AppColors.grey;

  Future<void> _navigateAndRefresh(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    // Re-fetch status after returning, in case something changed
    // (e.g. payout details were just saved).
    _loadStatus();
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
            if (_phone != null && _phone!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Center(
                child: Text(
                  _phone!,
                  style: const TextStyle(fontSize: 13, color: AppColors.grey),
                ),
              ),
            ],
            const SizedBox(height: 20),

            if (!_isLoadingStatus && _isSetupIncomplete) ...[
              _buildSetupReminderBanner(),
              const SizedBox(height: 20),
            ],

            _buildMenuTile(
              icon: Icons.person_outline,
              label: 'Edit Profile',
              onTap: () => _navigateAndRefresh(const EditProfileScreen()),
            ),
            const SizedBox(height: 24),

            _sectionLabel('Host Setup'),
            if (_isLoadingStatus)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildStatusTile(
                icon: Icons.verified_user_outlined,
                label: 'Identity Verification',
                statusText: _verificationLabel,
                statusColor: _verificationColor,
                isComplete: _status?['id_verification_status'] == 'verified' ||
                    _status?['phone_verified'] == true,
                onTap: () =>
                    _navigateAndRefresh(const HostVerifyIdentityScreen()),
              ),
              const SizedBox(height: 10),
              _buildStatusTile(
                icon: Icons.account_balance_outlined,
                label: 'Payout Details',
                statusText: _payoutLabel,
                statusColor: _payoutColor,
                isComplete: _status?['payout_setup_complete'] == true,
                onTap: () =>
                    _navigateAndRefresh(const HostPayoutDetailsScreen()),
              ),
              const SizedBox(height: 10),
              _buildStatusTile(
                icon: Icons.description_outlined,
                label: 'Host Agreement',
                statusText: _agreementLabel,
                statusColor: _agreementColor,
                isComplete: _status?['host_agreement_accepted'] == true,
                onTap: () =>
                    _navigateAndRefresh(const HostAgreementScreen()),
              ),
            ],

            const SizedBox(height: 28),
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

  Widget _buildSetupReminderBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Complete verification, payout details & host agreement to start hosting.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.dark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

  Widget _buildStatusTile({
    required IconData icon,
    required String label,
    required String statusText,
    required Color statusColor,
    required bool isComplete,
    required VoidCallback onTap,
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: AppColors.dark, size: 20),
                if (!isComplete)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.lightGrey, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
          ],
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
