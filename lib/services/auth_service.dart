import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/supabase_config.dart';

/// Wraps all Supabase auth calls so UI code never talks to
/// Supabase directly. Makes it easy to swap/extend later.
class AuthService {
  final SupabaseClient _client = SupabaseConfig.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  bool get isLoggedIn => currentUser != null;

  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
    String role = 'guest', // 'guest' or 'host'
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'role': role,
        // Hosts see a one-time onboarding carousel before reaching
        // HostHomeScreen; guests don't need this flag at all.
        'host_onboarding_completed': false,
      },
    );
  }

  /// 'guest' or 'host', read from the signed-in user's metadata
  /// (set during sign up). Defaults to 'guest' if missing, e.g. for
  /// accounts created before the role toggle existed.
  String get currentUserRole {
    final role = currentUser?.userMetadata?['role'] as String?;
    return role ?? 'guest';
  }

  /// Whether this host has already been through the onboarding
  /// carousel. Read from metadata (instant, no DB call) rather than
  /// the profiles table - same efficiency pattern as currentUserRole.
  /// Defaults to true for anyone without the flag at all (e.g.
  /// existing guest accounts, or hosts created before this feature
  /// existed) so nobody gets unexpectedly shown onboarding.
  bool get hasCompletedHostOnboarding {
    final value = currentUser?.userMetadata?['host_onboarding_completed'];
    if (value == null) return true;
    return value == true;
  }

  /// Marks onboarding as done in BOTH places that need to stay in
  /// sync - metadata for instant reads elsewhere in the app,
  /// host_profiles table as the source of truth (this flag is
  /// host-specific, so it lives in host_profiles, not profiles).
  Future<void> markHostOnboardingComplete() async {
    await _client.auth.updateUser(
      UserAttributes(data: {'host_onboarding_completed': true}),
    );

    final userId = currentUser?.id;
    if (userId != null) {
      await _client.from('host_profiles').upsert({
        'id': userId,
        'host_onboarding_completed': true,
      });
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Updates the user's name and phone in TWO places that need to
  /// stay in sync:
  /// 1. auth.users' metadata (via updateUser) - this is what
  ///    currentUser?.userMetadata reads from, used for the instant
  ///    "Welcome back, X" greeting on Home without an extra DB query.
  /// 2. the `profiles` table row - the actual source of truth used
  ///    by any future feature that queries user data via SQL
  ///    (e.g. showing a host's name on their listings).
  /// Reads the current user's profiles row - needed because `phone`
  /// only lives in the profiles table, not in auth metadata (unlike
  /// full_name, which we also mirror into user_metadata for instant
  /// access elsewhere in the app).
  Future<Map<String, dynamic>?> getMyProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    return await _client.from('profiles').select().eq('id', userId).maybeSingle();
  }

  Future<void> updateProfile({
    required String fullName,
    String? phone,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to update your profile.');
    }

    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );

    await _client.from('profiles').update({
      'full_name': fullName,
      if (phone != null) 'phone': phone,
    }).eq('id', userId);

    // host_profiles keeps its OWN copy of full_name (duplicated, not
    // just referenced), so it needs to be updated here too whenever
    // a host edits their name - otherwise the two tables would drift
    // out of sync with each other.
    if (currentUserRole == 'host') {
      await _client.from('host_profiles').update({
        'full_name': fullName,
      }).eq('id', userId);
    }
  }
}
