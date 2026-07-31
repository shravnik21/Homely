import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:homely_app/config/app_theme.dart';

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

const List<_Faq> _faqs = [
  _Faq(
    'How do I book a place?',
    'Open a place from the Home screen, choose your dates and guest count '
        'on the booking screen, then confirm your booking. You\'ll see it '
        'right away under My Bookings.',
  ),
  _Faq(
    'How do I cancel or change a booking?',
    'Go to My Bookings, open the booking you want to change, and use the '
        'cancel or modify option there. Refund eligibility depends on the '
        'listing\'s cancellation policy shown at checkout.',
  ),
  _Faq(
    'I forgot my password. What do I do?',
    'On the login screen, tap "Forgot password" (or go to Settings > '
        'Change Password if you\'re already logged in) and we\'ll email you '
        'a reset link.',
  ),
  _Faq(
    'How do I update my profile details?',
    'Go to Settings > Edit Profile to update your name, phone number and '
        'photo.',
  ),
  _Faq(
    'Is my payment information safe?',
    'Yes. Homely does not store your card details on our servers; '
        'payments are handled securely by our payment partners.',
  ),
  _Faq(
    'How do I contact a host?',
    'Once you\'ve booked a place, host contact details or an in-app way '
        'to reach them will be available from that booking\'s details '
        'screen.',
  ),
];

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  int? _expandedIndex;

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
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
          'Help & Support',
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Get in touch',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.grey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            _contactTile(
              icon: Icons.email_outlined,
              label: 'Email us',
              value: 'support@homelyapp.com',
              onTap: () => _copyToClipboard(
                  'support@homelyapp.com', 'Support email'),
            ),
            const SizedBox(height: 10),
            _contactTile(
              icon: Icons.phone_outlined,
              label: 'Call us',
              value: '+91 98765 43210',
              onTap: () =>
                  _copyToClipboard('+919876543210', 'Support number'),
            ),
            const SizedBox(height: 10),
            _contactTile(
              icon: Icons.access_time,
              label: 'Support hours',
              value: 'Mon–Sat, 9 AM – 7 PM IST',
              onTap: null,
            ),
            const SizedBox(height: 28),
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.grey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < _faqs.length; i++) ...[
              _faqTile(index: i, faq: _faqs[i]),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.dark,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.copy, color: AppColors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _faqTile({required int index, required _Faq faq}) {
    final expanded = _expandedIndex == index;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _expandedIndex = expanded ? null : index;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      faq.question,
                      style: const TextStyle(
                        color: AppColors.dark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.grey,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                faq.answer,
                style: const TextStyle(
                  color: AppColors.grey,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
