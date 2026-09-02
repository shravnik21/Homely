import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  /// Custom URL scheme the app registers natively (see
  /// android/app/src/main/AndroidManifest.xml's extra <intent-filter>
  /// and ios/Runner/Info.plist's CFBundleURLTypes) so tapping the
  /// "Reset Password" link in the recovery email opens THIS app
  /// instead of a browser. Passed as `redirectTo` when requesting the
  /// reset email; supabase_flutter watches for the OS handing this
  /// URL back to the app and turns it into a `passwordRecovery`
  /// auth-state event (see main.dart) - no manual link-parsing needed.
  ///
  /// Also needs to be added to Supabase Dashboard → Authentication →
  /// URL Configuration → Redirect URLs, or Supabase will reject it.
  static const String passwordResetRedirectUrl = 'homelyapp://reset-callback';

  static Future<void> initialize() async {
    await dotenv.load(fileName: ".env");//dotenv allows to access environment variables from env file 

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }

  // Quick access to the client anywhere in the app
  static SupabaseClient get client => Supabase.instance.client;
}
