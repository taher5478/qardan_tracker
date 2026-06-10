import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import 'settings_service.dart';

/// Google sign-in → Supabase Auth session, plus profile / PIN-recovery sync.
///
/// Gives you a server record of who signed in, and mirrors the PIN recovery
/// hash so you can help a locked-out user reset it. Subscription state is read
/// separately (Dodo webhook → subscriptions table).
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  final GoogleSignIn _gsi = GoogleSignIn(
    serverClientId:
        kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
    scopes: const ['email'],
  );

  SupabaseClient get _sb => Supabase.instance.client;

  User? get currentUser => _sb.auth.currentUser;
  bool get isSignedIn => currentUser != null;
  String? get email => currentUser?.email;

  /// Sign in with Google and open a Supabase session. Returns false on cancel
  /// or if login isn't configured yet (no server client id / provider).
  Future<bool> signInWithGoogle() async {
    if (kGoogleServerClientId.isEmpty) return false;
    try {
      final account = await _gsi.signIn();
      if (account == null) return false; // user cancelled
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return false;

      await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
      );
      await pushProfile();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
    try {
      await _gsi.signOut();
    } catch (_) {}
  }

  /// Upsert the user's profile and mirror the local PIN recovery hash. Safe
  /// no-op when signed out or offline.
  Future<void> pushProfile() async {
    final user = currentUser;
    if (user == null) return;
    try {
      await _sb.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'recovery_hash': AppSettings.instance.recoveryHashRaw,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Best-effort; profile also auto-creates via the signup trigger.
    }
  }
}
