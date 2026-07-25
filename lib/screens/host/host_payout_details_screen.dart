import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/host_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';

class HostPayoutDetailsScreen extends StatefulWidget {
  const HostPayoutDetailsScreen({super.key});

  @override
  State<HostPayoutDetailsScreen> createState() =>
      _HostPayoutDetailsScreenState();
}

class _HostPayoutDetailsScreenState extends State<HostPayoutDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostService = HostService();

  final _accountHolderController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscController = TextEditingController();
  final _upiController = TextEditingController();

  bool _isLoadingExisting = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingDetails();
  }

  Future<void> _loadExistingDetails() async {
    try {
      final profile = await _hostService.getMyHostProfile();
      if (mounted && profile != null) {
        setState(() {
          _accountHolderController.text =
              profile['bank_account_holder'] as String? ?? '';
          _accountNumberController.text =
              profile['bank_account_number'] as String? ?? '';
          _ifscController.text = profile['bank_ifsc'] as String? ?? '';
          _upiController.text = profile['upi_id'] as String? ?? '';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _hostService.updatePayoutDetails(
        accountHolder: _accountHolderController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        ifsc: _ifscController.text.trim(),
        upiId: _upiController.text.trim().isEmpty
            ? null
            : _upiController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout details saved')),
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
          'Payout Details',
          style: TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: _isLoadingExisting
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.science_outlined,
                                size: 18, color: Colors.orange),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Test Mode - no real payments are processed. These details are stored for demo purposes only.',
                                style: TextStyle(
                                    fontSize: 12.5, color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Where should your earnings go?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        controller: _accountHolderController,
                        label: 'Account holder name',
                        hint: 'As it appears on your bank account',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      CustomTextField(
                        controller: _accountNumberController,
                        label: 'Bank account number',
                        hint: 'e.g. 000123456789',
                        keyboardType: TextInputType.number,
                        validator: (v) => (v == null || v.trim().length < 6)
                            ? 'Enter a valid account number'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      CustomTextField(
                        controller: _ifscController,
                        label: 'IFSC code',
                        hint: 'e.g. HDFC0001234',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      CustomTextField(
                        controller: _upiController,
                        label: 'UPI ID (optional)',
                        hint: 'e.g. yourname@upi',
                      ),
                      const SizedBox(height: 32),
                      PrimaryButton(
                        text: 'Save Payout Details',
                        isLoading: _isSaving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
