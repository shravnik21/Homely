import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';
import 'package:homely_app/utils/network_error_helper.dart';

/// Password recovery, step 2 - only ever pushed by main.dart's
/// listener the moment Supabase reports `AuthChangeEvent
/// .passwordRecovery`, which fires when the app is opened via the
/// magic link from ForgotPasswordScreen's email. That event means
/// there's already a short-lived, authenticated recovery session in
/// place, proving the person tapping the link owns the inbox it was
/// sent to - so this screen just needs the new password itself, no
/// code or email re-entry.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await _authService.updatePasswordAfterReset(_passwordController.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset. Please log in again.')),
      );
      // This screen was pushed on top of whatever was on screen when
      // the magic link opened the app, so pop everything back to the
      // very first route (the splash/login screen underneath).
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      // Supabase's own message here (e.g. "Auth session missing" if
      // the recovery link has expired) is already clear enough to
      // show directly, same as login_screen.dart's handling.
      _showError(e.message);
    } catch (e) {
      _showError(isNetworkError(e) ? noInternetMessage : 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The person only got here via a one-time recovery session -
      // swiping/back-navigating away without finishing leaves that
      // session dangling, so keep them on this screen until they
      // either finish or the app is backgrounded/closed.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          foregroundColor: AppColors.dark,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Set a new password',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "You're verified - choose a new password for your account.",
                    style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 32),

                  CustomTextField(
                    controller: _passwordController,
                    label: 'New password',
                    hint: 'Enter a new password',
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  CustomTextField(
                    controller: _confirmController,
                    label: 'Confirm new password',
                    hint: 'Re-enter your new password',
                    obscureText: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),
                  PrimaryButton(
                    text: 'Reset Password',
                    isLoading: _isSubmitting,
                    onPressed: _resetPassword,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
