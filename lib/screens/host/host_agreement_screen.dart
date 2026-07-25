import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/host_service.dart';
import 'package:homely_app/widgets/primary_button.dart';

const _agreementText = '''
Homely Host Agreement (Demo)

This is a placeholder Host Agreement for demonstration purposes. In a production app, this would be actual legal terms drafted with a lawyer, covering:

1. Host Responsibilities
You agree to accurately represent your listing, keep your calendar up to date, and honor confirmed bookings.

2. Fees
Homely charges a service fee on completed bookings, deducted automatically before payout.

3. Cancellations
Cancelling a confirmed booking as a host may affect your listing's visibility and is subject to the cancellation policy you select per listing.

4. Guest Conduct
You may set house rules for your property, which guests are expected to follow during their stay.

5. Payouts
Payouts are sent to the bank/UPI details you provide, typically after a guest's check-in is confirmed.

6. Content Ownership
Photos and descriptions you upload remain yours, but you grant Homely a license to display them within the app.

7. Termination
Homely may suspend or remove a listing that violates these terms or applicable law.

By accepting, you confirm you have read and agree to these terms as a host on Homely.
''';

class HostAgreementScreen extends StatefulWidget {
  const HostAgreementScreen({super.key});

  @override
  State<HostAgreementScreen> createState() => _HostAgreementScreenState();
}

class _HostAgreementScreenState extends State<HostAgreementScreen> {
  final HostService _hostService = HostService();
  bool _hasRead = false;
  bool _isSaving = false;

  Future<void> _accept() async {
    setState(() => _isSaving = true);
    try {
      await _hostService.acceptHostAgreement();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host Agreement accepted')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          'Host Agreement',
          style: TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _agreementText.trim(),
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.dark,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _hasRead,
                        activeColor: AppColors.primary,
                        onChanged: (v) =>
                            setState(() => _hasRead = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'I have read and agree to the Homely Host Agreement',
                          style: TextStyle(fontSize: 12.5, color: AppColors.dark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    text: 'Accept & Continue',
                    isLoading: _isSaving,
                    onPressed: _hasRead ? _accept : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
