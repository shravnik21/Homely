import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/services/host_service.dart';
import 'package:homely_app/screens/host/host_profile_screen.dart';

/// Landing screen for hosts, shown instead of the guest [HomeScreen]
/// after logging in / signing up with the "Host" role selected.
class HostHomeScreen extends StatefulWidget {
  const HostHomeScreen({super.key});

  @override
  State<HostHomeScreen> createState() => _HostHomeScreenState();
}

class _HostHomeScreenState extends State<HostHomeScreen> {
  final AuthService _authService = AuthService();
  final HostService _hostService = HostService();

  // Defaults to true (assume incomplete) until the real status loads,
  // so the reminder dot doesn't briefly flash "all good" before
  // flipping - safer default for a "needs attention" indicator.
  bool _hasIncompleteSetup = true;

  @override
  void initState() {
    super.initState();
    _loadSetupStatus();
  }

  Future<void> _loadSetupStatus() async {
    final incomplete = await _hostService.hasIncompleteSetup();
    if (mounted) setState(() => _hasIncompleteSetup = incomplete);
  }

  String get _displayName {
    final meta = _authService.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return 'there';
    return name.trim().split(' ').first;
  }

  String get _initial {
    final meta = _authService.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return '?';
    return name.trim()[0].toUpperCase();
  }

  void _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostProfileScreen()),
    );
    // Re-check after returning, in case they just completed a step
    // (e.g. saved payout details) - so the dot disappears immediately
    // without needing to reopen the app.
    _loadSetupStatus();
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            if (_hasIncompleteSetup) ...[
              _buildSetupReminderBanner(),
              const SizedBox(height: 20),
            ],
            _buildStatsRow(),
            const SizedBox(height: 28),
            _buildAddListingCard(),
            const SizedBox(height: 28),
            const Text(
              'Your Listings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 12),
            _buildEmptyListingsState(),
            const SizedBox(height: 28),
            const Text(
              'Recent Bookings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 12),
            _buildEmptyBookingsState(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back, host 👋',
              style: TextStyle(color: AppColors.primary, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              _displayName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: _openProfile,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_hasIncompleteSetup)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetupReminderBanner() {
    return GestureDetector(
      onTap: _openProfile,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withOpacity(0.25)),
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
            const Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(label: 'Listings', value: '0')),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(label: 'Bookings', value: '0')),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(label: 'Earnings', value: '₹0')),
      ],
    );
  }

  Widget _buildStatCard({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAddListingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'List your place on Homely',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start earning by hosting guests at your farmhouse, villa or apartment.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 46),
            ),
            onPressed: () => _comingSoon('Adding a listing'),
            child: const Text('Add a Listing'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyListingsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Text(
        "You haven't added any listings yet.",
        style: TextStyle(color: AppColors.grey, fontSize: 13),
      ),
    );
  }

  Widget _buildEmptyBookingsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Text(
        'No bookings yet. They will show up here once guests book your place.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.grey, fontSize: 13),
      ),
    );
  }
}
