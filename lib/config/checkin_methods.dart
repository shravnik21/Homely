import 'package:flutter/material.dart';

/// One selectable check-in method - shown as a card in
/// ListingWizardScreen's Highlights step, and looked up by [value] to
/// render the right icon/label on PlaceDetailScreen's highlight row.
/// A fixed catalog (rather than free text) so the guest-facing
/// display always has a matching icon, while [Place.checkinDetails]
/// still gives the host room to describe exactly how it works for
/// their own place.
///
/// [subtitle] and [guestSubtitle] describe the exact same method from
/// two different points of view, and deliberately say different
/// things - [subtitle] is what the HOST reads while picking a method
/// in the wizard ("Guest enters a code you provide"), [guestSubtitle]
/// is what the GUEST reads on the published listing page ("You'll
/// enter a code provided by your host"). Only used as a fallback on
/// the guest side - see PlaceDetailScreen - and only when the host
/// hasn't typed their own [Place.checkinDetails].
class CheckinMethodOption {
  final String value;
  final String label;
  final String subtitle;
  final String guestSubtitle;
  final IconData icon;

  const CheckinMethodOption({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.guestSubtitle,
    required this.icon,
  });
}

const List<CheckinMethodOption> kCheckinMethods = [
  CheckinMethodOption(
    value: 'smart_lock',
    label: 'Smart lock / keypad',
    subtitle: 'Guest enters a code you provide - no key needed.',
    guestSubtitle: "You'll enter a code provided by your host - no key needed.",
    icon: Icons.dialpad_rounded,
  ),
  CheckinMethodOption(
    value: 'lockbox',
    label: 'Lockbox',
    subtitle: 'Key is stored in a coded box on-site.',
    guestSubtitle:
        "Your key will be waiting in a coded lockbox on-site - your host will share the code.",
    icon: Icons.lock_outline_rounded,
  ),
  CheckinMethodOption(
    value: 'host_greets',
    label: 'Host or caretaker greets you',
    subtitle: 'Someone meets the guest in person at check-in.',
    guestSubtitle: 'Your host or their caretaker will meet you in person at check-in.',
    icon: Icons.emoji_people_rounded,
  ),
  CheckinMethodOption(
    value: 'building_staff',
    label: 'Building security / doorman',
    subtitle: 'Building staff lets the guest in.',
    guestSubtitle: "Building security will let you in when you arrive.",
    icon: Icons.apartment_rounded,
  ),
  CheckinMethodOption(
    value: 'other',
    label: 'Other',
    subtitle: 'Describe your own check-in method below.',
    guestSubtitle: "Your host will share their check-in instructions with you.",
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
    guestSubtitle: '',
    icon: Icons.key_rounded,
  );
}
