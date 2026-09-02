import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';
import 'package:homely_app/utils/network_error_helper.dart';

/// Password recovery, step 1: collects the account's email and asks
/// Supabase to send it a magic link. Tapping that link from the
/// email opens this app directly (via the custom URL scheme
/// registered in AndroidManifest.xml / Info.plist) and signs the
/// person into a short-lived "recovery" session - main.dart's
/// `AuthChangeEvent.passwordRecovery` listener catches that moment
/// and pushes ResetPasswordScreen for them to actually set the new
/// password. This screen's own job ends at "email sent"; it never
/// navigates forward itself.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _isResending = false;

  /// Once the link has been sent, we swap to a "check your email"
  /// state rather than a new screen - there's nothing further for
  /// this screen to collect, and the actual next step (setting the
  /// new password) only happens once the user taps the email link.
  bool _linkSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.resetPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() => _linkSent = true);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(isNetworkError(e) ? noInternetMessage : 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendLink() async {
    setState(() => _isResending = true);
    try {
      await _authService.resetPassword(_emailController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent a new link to ${_emailController.text.trim()}.')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(isNetworkError(e) ? noInternetMessage : "Couldn't resend the link. Try again.");
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _linkSent ? _buildSentState() : _buildFormState(),
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Forgot password?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            "Enter the email on your account and we'll send you a "
            "link to reset your password.",
            style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 32),

          CustomTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Email is required';
              }
              if (!value.contains('@')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),

          const SizedBox(height: 24),
          PrimaryButton(
            text: 'Send Reset Link',
            isLoading: _isLoading,
            onPressed: _sendLink,
          ),
        ],
      ),
    );
  }

  Widget _buildSentState() {
    final email = _emailController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 56),
        const SizedBox(height: 20),
        const Text(
          'Check your email',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          "We've sent a password reset link to $email. Open it on "
          "this device to set a new password - it'll bring you "
          "straight back into the app.",
          style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _isResending ? null : _resendLink,
            child: Text(_isResending ? 'Resending...' : "Didn't get it? Resend"),
          ),
        ),
      ],
    );
  }
}
