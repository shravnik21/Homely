import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/host_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';

class HostVerifyIdentityScreen extends StatefulWidget {
  const HostVerifyIdentityScreen({super.key});

  @override
  State<HostVerifyIdentityScreen> createState() =>
      _HostVerifyIdentityScreenState();
}

class _HostVerifyIdentityScreenState extends State<HostVerifyIdentityScreen> {
  final HostService _hostService = HostService();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _picker = ImagePicker();

  bool _isLoadingInitial = true;
  bool _otpSent = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _phoneVerified = false;
  String? _verifiedPhoneNumber;

  File? _pickedImage;
  bool _isUploadingId = false;
  bool _idSubmitted = false;

  @override
  void initState() {
    super.initState();
    _loadExistingStatus();
  }

  // Without this, reopening the screen after already verifying would
  // just show the empty form again - this checks what's already
  // saved so the verified state actually persists across visits.
  Future<void> _loadExistingStatus() async {
    try {
      final data = await _hostService.getMyHostProfileWithAccountInfo();
      final profileInfo = data?['profiles'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _phoneVerified = data?['phone_verified'] == true;
          _verifiedPhoneNumber = profileInfo?['phone'] as String?;
          final idStatus = data?['id_verification_status'];
          _idSubmitted = idStatus == 'pending' || idStatus == 'verified';
        });
      }
    } catch (_) {
      // Non-fatal - leaves the form visible if this fails.
    } finally {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.trim().length < 10) {
      _showSnack('Enter a valid phone number', isError: true);
      return;
    }
    setState(() => _isSendingOtp = true);
    // MOCK: no real SMS provider is wired up yet - see HostService for
    // notes on connecting a real one (e.g. Twilio via Supabase Auth).
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      _otpSent = true;
    });
    _showSnack('Demo mode: enter any 6-digit code to continue');
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length != 6) {
      _showSnack('Enter the 6-digit code', isError: true);
      return;
    }
    setState(() => _isVerifyingOtp = true);
    try {
      await _hostService.markPhoneVerified(_phoneController.text.trim());
      if (!mounted) return;
      setState(() {
        _phoneVerified = true;
        _verifiedPhoneNumber = _phoneController.text.trim();
        _isVerifyingOtp = false;
      });
      _showSnack('Phone number verified');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifyingOtp = false);
      _showSnack('Could not verify: $e', isError: true);
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      setState(() => _pickedImage = File(image.path));
    }
  }

  Future<void> _uploadId() async {
    if (_pickedImage == null) return;
    setState(() => _isUploadingId = true);
    try {
      await _hostService.uploadIdDocument(_pickedImage!);
      if (!mounted) return;
      setState(() {
        _isUploadingId = false;
        _idSubmitted = true;
      });
      _showSnack('ID submitted for review');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingId = false);
      _showSnack('Upload failed: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
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
          'Verify Identity',
          style: TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Verifying your identity helps guests trust your listings. This step uses demo/mock verification for now.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ---- Phone OTP section ----
              const Text('Phone Number',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
              const SizedBox(height: 4),
              const Text(
                'We\'ll send a one-time code to confirm it\'s really you.',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
              const SizedBox(height: 14),

              if (_phoneVerified) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 18, color: AppColors.dark),
                      const SizedBox(width: 10),
                      Text(
                        _verifiedPhoneNumber ?? '—',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildVerifiedBanner('Phone number verified'),
              ] else ...[
                CustomTextField(
                  controller: _phoneController,
                  label: 'Phone number',
                  hint: 'e.g. 9876543210',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                if (!_otpSent)
                  PrimaryButton(
                    text: 'Send OTP',
                    isLoading: _isSendingOtp,
                    onPressed: _sendOtp,
                  )
                else ...[
                  CustomTextField(
                    controller: _otpController,
                    label: 'Enter 6-digit code',
                    hint: '••••••',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    text: 'Verify',
                    isLoading: _isVerifyingOtp,
                    onPressed: _verifyOtp,
                  ),
                ],
              ],

              const SizedBox(height: 32),
              const Divider(color: AppColors.lightGrey),
              const SizedBox(height: 24),

              // ---- Government ID upload section ----
              const Text('Government ID (Optional)',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark)),
              const SizedBox(height: 4),
              const Text(
                'Upload a photo of a valid ID. This is reviewed manually and adds a stronger trust badge to your profile.',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
              const SizedBox(height: 14),

              if (_idSubmitted)
                _buildVerifiedBanner('ID submitted - pending review',
                    icon: Icons.hourglass_top, color: Colors.orange)
              else ...[
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.lightGrey,
                      borderRadius: BorderRadius.circular(16),
                      image: _pickedImage != null
                          ? DecorationImage(
                              image: FileImage(_pickedImage!),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: _pickedImage == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.upload_file_outlined,
                                  size: 32, color: AppColors.grey),
                              SizedBox(height: 8),
                              Text('Tap to select a photo',
                                  style: TextStyle(
                                      color: AppColors.grey, fontSize: 13)),
                            ],
                          )
                        : null,
                  ),
                ),
                if (_pickedImage != null) ...[
                  const SizedBox(height: 12),
                  PrimaryButton(
                    text: 'Submit for Review',
                    isLoading: _isUploadingId,
                    onPressed: _uploadId,
                  ),
                ],
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedBanner(String text,
      {IconData icon = Icons.check_circle, Color color = Colors.green}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
