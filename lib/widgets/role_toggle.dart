import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';

/// Which kind of account the person is logging in / signing up as.
/// Drives which Home Screen they land on after auth succeeds.
enum UserRole { guest, host }

extension UserRoleX on UserRole {
  /// Stored in Supabase user metadata (and mirrored to `profiles.role`)
  /// so the app can tell guests and hosts apart later on.
  String get value => this == UserRole.host ? 'host' : 'guest';
}

/// Two rounded pill buttons side by side, e.g. "You are a Guest" /
/// "You are a Host". Tapping one selects it; the other is deselected.
class RoleToggle extends StatelessWidget {
  final UserRole selectedRole;
  final ValueChanged<UserRole> onChanged;
  final String guestLabel;
  final String hostLabel;

  const RoleToggle({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.guestLabel = 'You are a Guest',
    this.hostLabel = 'You are a Host',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RolePillButton(
            label: guestLabel,
            isSelected: selectedRole == UserRole.guest,
            onTap: () => onChanged(UserRole.guest),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RolePillButton(
            label: hostLabel,
            isSelected: selectedRole == UserRole.host,
            onTap: () => onChanged(UserRole.host),
          ),
        ),
      ],
    );
  }
}

class _RolePillButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RolePillButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? AppColors.white : AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
