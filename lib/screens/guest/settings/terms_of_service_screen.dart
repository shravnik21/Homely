import 'package:flutter/material.dart';
import 'package:homely_app/screens/guest/settings/legal_document_screen.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Terms of Service',
      lastUpdated: 'July 18, 2026',
      intro:
          'Welcome to Homely. These Terms of Service ("Terms") govern your '
          'use of the Homely app for discovering and booking farmhouses, '
          'flats, apartments and villas. By creating an account or using '
          'Homely, you agree to these Terms. If you do not agree, please '
          'do not use the app.',
      sections: [
        LegalSection(
          heading: 'Using Homely',
          body:
              'You must be at least 18 years old and able to form a '
              'binding contract to create an account. You\'re responsible '
              'for keeping your login credentials confidential and for all '
              'activity that happens under your account. Let us know '
              'immediately if you suspect unauthorized use.',
        ),
        LegalSection(
          heading: 'Bookings',
          body:
              'When you book a place through Homely, you\'re entering into '
              'an agreement with the host of that place, and Homely acts as '
              'the platform connecting you. Availability, pricing and house '
              'rules are set by hosts and shown to you before you confirm a '
              'booking. Please review all details carefully before '
              'booking, as cancellation and refund terms may vary by '
              'listing.',
        ),
        LegalSection(
          heading: 'Cancellations and Refunds',
          body:
              'Cancellation windows and refund eligibility are shown on the '
              'booking screen at the time you book. Requests to cancel or '
              'modify a booking should be made as early as possible through '
              'My Bookings or Help & Support.',
        ),
        LegalSection(
          heading: 'Your Conduct',
          body:
              'You agree not to misuse the app, including attempting to '
              'access accounts or data that aren\'t yours, submitting false '
              'booking requests, interfering with the app\'s normal '
              'operation, or using Homely for any unlawful purpose. We may '
              'suspend or terminate accounts that violate these Terms.',
        ),
        LegalSection(
          heading: 'Content You Submit',
          body:
              'If you submit content such as a profile photo, review or '
              'special request, you confirm you have the right to share it '
              'and grant Homely a license to use it solely to operate and '
              'improve the app.',
        ),
        LegalSection(
          heading: 'Disclaimers',
          body:
              'Homely lists places provided by third-party hosts and does '
              'not own or manage these properties. We do our best to keep '
              'listing information accurate, but we don\'t guarantee the '
              'condition, safety or legality of any listed place. The app '
              'is provided "as is" without warranties of any kind.',
        ),
        LegalSection(
          heading: 'Limitation of Liability',
          body:
              'To the extent permitted by law, Homely is not liable for any '
              'indirect, incidental or consequential damages arising from '
              'your use of the app or a booking made through it.',
        ),
        LegalSection(
          heading: 'Changes to These Terms',
          body:
              'We may update these Terms occasionally. If changes are '
              'material, we\'ll let you know in the app or by email before '
              'they take effect. Continuing to use Homely after changes '
              'take effect means you accept the updated Terms.',
        ),
        LegalSection(
          heading: 'Contact Us',
          body:
              'Questions about these Terms? Reach us from Help & Support in '
              'the app, or email support@homelyapp.com.',
        ),
      ],
    );
  }
}
