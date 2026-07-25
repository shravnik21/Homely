import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/supabase_config.dart';

/// Handles the host-specific setup steps: identity verification,
/// payout details, and host agreement acceptance. Kept separate from
/// AuthService (which handles generic auth/profile concerns) since
/// this is a distinct responsibility that only applies to hosts -
/// same single-responsibility reasoning as PlacesService vs
/// BookingService being separate files.
class HostService {
  final SupabaseClient _client = SupabaseConfig.client;

  String? get _userId => _client.auth.currentUser?.id;

  // ---------------- Identity verification ----------------

  /// MOCK phone verification for now - there's no real SMS provider
  /// wired up (that requires a paid service like Twilio, configured
  /// on the Supabase project's Auth settings). This simulates the
  /// flow end-to-end so the UI/UX is real, and just accepts any
  /// 6-digit code as "correct". Swap this out for Supabase's real
  /// phone-auth OTP flow once an SMS provider is configured.
  Future<void> markPhoneVerified(String phoneNumber) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not logged in.');

    await _client.from('profiles').update({
      'phone': phoneNumber,
      'phone_verified': true,
    }).eq('id', userId);
  }

  /// Uploads a government ID photo to Supabase Storage, under a
  /// folder named after the user's own id (required by the RLS
  /// policies in schema_host_verification.sql), then records the
  /// file's path and sets status to 'pending' - a real app would
  /// have an admin/manual review step move this to 'verified'.
  Future<void> uploadIdDocument(File imageFile) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not logged in.');

    final ext = imageFile.path.split('.').last;
    final path = '$userId/id_document.$ext';

    await _client.storage.from('host-documents').upload(
          path,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    await _client.from('profiles').update({
      'id_document_url': path,
      'id_verification_status': 'pending',
    }).eq('id', userId);
  }

  // ---------------- Payout details ----------------

  Future<void> updatePayoutDetails({
    required String accountHolder,
    required String accountNumber,
    required String ifsc,
    String? upiId,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not logged in.');

    await _client.from('profiles').update({
      'bank_account_holder': accountHolder,
      'bank_account_number': accountNumber,
      'bank_ifsc': ifsc,
      'upi_id': upiId,
      'payout_setup_complete': true,
    }).eq('id', userId);
  }

  // ---------------- Host agreement ----------------

  Future<void> acceptHostAgreement() async {
    final userId = _userId;
    if (userId == null) throw Exception('Not logged in.');

    await _client.from('profiles').update({
      'host_agreement_accepted': true,
      'host_agreement_accepted_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// True if any of the three mandatory host setup steps (identity
  /// verification, payout details, host agreement) is still
  /// incomplete. Used to show a red "needs attention" dot on the
  /// host's profile icon - same pattern most real apps use for
  /// notification badges.
  Future<bool> hasIncompleteSetup() async {
    final status = await getHostSetupStatus();
    if (status == null) return true;

    final verified = (status['id_verification_status'] == 'verified') ||
        (status['phone_verified'] == true);
    final payoutDone = status['payout_setup_complete'] == true;
    final agreementDone = status['host_agreement_accepted'] == true;

    return !(verified && payoutDone && agreementDone);
  }

  // ---------------- Combined status read ----------------

  /// One query, read once by HostProfileScreen to show all three
  /// status badges (verification / payout / agreement) without
  /// three separate round trips.
  Future<Map<String, dynamic>?> getHostSetupStatus() async {
    final userId = _userId;
    if (userId == null) return null;
    return await _client
        .from('profiles')
        .select(
            'id_verification_status, phone_verified, payout_setup_complete, host_agreement_accepted')
        .eq('id', userId)
        .maybeSingle();
  }
}
