import 'package:flutter/material.dart';

/// One selectable check-in method - shown as a card in
/// ListingWizardScreen's Highlights step, and looked up by [value] to
/// render the right icon/label on PlaceDetailScreen's highlight row.
/// A fixed catalog (rather than free text) so the guest-facing
/// display always has a matching icon, while [Place.checkinDetails]
/// still gives the host room to describe exactly how it works for
/// their own place.
class CheckinMethodOption {
  final String value;
  final String label;
  final String subtitle;
  final IconData icon;

  const CheckinMethodOption({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
  });
}

const List<CheckinMethodOption> kCheckinMethods = [
  CheckinMethodOption(
    value: 'smart_lock',
    label: 'Smart lock / keypad',
    subtitle: 'Guest enters a code you provide - no key needed.',
    icon: Icons.dialpad_rounded,
  ),
  CheckinMethodOption(
    value: 'lockbox',
    label: 'Lockbox',
    subtitle: 'Key is stored in a coded box on-site.',
    icon: Icons.lock_outline_rounded,
  ),
  CheckinMethodOption(
    value: 'host_greets',
    label: 'Host or caretaker greets you',
    subtitle: 'Someone meets the guest in person at check-in.',
    icon: Icons.emoji_people_rounded,
  ),
  CheckinMethodOption(
    value: 'building_staff',
    label: 'Building security / doorman',
    subtitle: 'Building staff lets the guest in.',
    icon: Icons.apartment_rounded,
  ),
  CheckinMethodOption(
    value: 'other',
    label: 'Other',
    subtitle: 'Describe your own check-in method below.',
    icon: Icons.edit_note_rounded,
  ),
];

/// Looks up the display info for a stored `checkin_method` value -
/// falls back to a generic key icon/label if the place has a method
/// value this catalog doesn't currently recognise (e.g. an older
/// value from before this list changed), rather than crashing or
/// showing nothing.
CheckinMethodOption checkinMethodFor(String value) {
  for (final option in kCheckinMethods) {
    if (option.value == value) return option;
  }
  return CheckinMethodOption(
    value: value,
    label: 'Self check-in',
    subtitle: '',
    icon: Icons.key_rounded,
  );
}
