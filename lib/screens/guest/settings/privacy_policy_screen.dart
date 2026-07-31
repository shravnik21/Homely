import 'package:flutter/material.dart';
import 'package:homely_app/screens/guest/settings/legal_document_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Privacy Policy',
      lastUpdated: 'July 18, 2026',
      intro:
          'Homely ("we", "us", "our") helps you discover and book farmhouses, '
          'flats, apartments and villas. This Privacy Policy explains what '
          'information we collect when you use the Homely app, how we use '
          'it, and the choices you have. By creating an account or using '
          'Homely, you agree to the practices described here.',
      sections: [
        LegalSection(
          heading: 'Information We Collect',
          body:
              'Account information: your full name, email address, phone '
              'number and password (stored securely, never in plain text) '
              'when you sign up.\n\n'
              'Booking information: the places you view, save or book, your '
              'check-in and check-out dates, guest counts and any special '
              'requests you submit.\n\n'
              'Profile information: any details you choose to add to your '
              'profile, such as a display photo or bio.\n\n'
              'Usage information: how you interact with the app (screens '
              'viewed, searches made, crash and performance data) so we can '
              'keep Homely reliable.',
        ),
        LegalSection(
          heading: 'How We Use Your Information',
          body:
              'We use your information to create and manage your account, '
              'process and confirm bookings, show you relevant places, '
              'communicate booking updates and support responses, and '
              'improve the app\'s performance and features. We do not sell '
              'your personal information to third parties.',
        ),
        LegalSection(
          heading: 'How We Store and Protect Your Data',
          body:
              'Your data is stored with our backend infrastructure provider '
              'using industry-standard encryption in transit and at rest. '
              'Access to your data is restricted to what is needed to '
              'operate the app. While we take reasonable steps to protect '
              'your information, no method of transmission or storage is '
              '100% secure.',
        ),
        LegalSection(
          heading: 'Sharing Your Information',
          body:
              'We share booking details (such as your name and contact '
              'information) with the host of a place you book, only to the '
              'extent needed to fulfil that booking. We may also share '
              'information with service providers who help us run Homely '
              '(such as hosting and infrastructure providers), or when '
              'required to comply with the law.',
        ),
        LegalSection(
          heading: 'Your Choices and Rights',
          body:
              'You can view and update your profile information at any '
              'time from Edit Profile. You can request a copy of your data '
              'or ask us to delete your account and associated data by '
              'contacting support. You can also control push notification '
              'preferences from Settings.',
        ),
        LegalSection(
          heading: 'Data Retention',
          body:
              'We retain your account and booking information for as long '
              'as your account is active, or as needed to provide the app, '
              'resolve disputes and comply with our legal obligations. If '
              'you delete your account, we remove or anonymize your '
              'personal data except where retention is required by law.',
        ),
        LegalSection(
          heading: 'Children\'s Privacy',
          body:
              'Homely is not directed at children under 18, and we do not '
              'knowingly collect personal information from children.',
        ),
        LegalSection(
          heading: 'Changes to This Policy',
          body:
              'We may update this Privacy Policy from time to time. If we '
              'make material changes, we\'ll notify you in the app or by '
              'email before they take effect.',
        ),
        LegalSection(
          heading: 'Contact Us',
          body:
              'If you have questions about this Privacy Policy or how your '
              'data is handled, reach out to us from Help & Support in the '
              'app, or email support@homelyapp.com.',
        ),
      ],
    );
  }
}
