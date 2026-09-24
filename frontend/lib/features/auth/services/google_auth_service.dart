import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The Web OAuth client id — client_type 3 in
/// frontend/android/app/google-services.json. Passed as `serverClientId`
/// so Google issues an ID token whose `aud` claim the backend can verify
/// against GOOGLE_OAUTH_CLIENT_ID (see backend/core/google_auth.py). The
/// Android client id itself doesn't need to be passed here — the
/// google_sign_in_android plugin reads it automatically from
/// google-services.json.
const String _googleWebClientId =
    '189785138919-71ull6g1nujcculqhe3l14udr6kqiktr.apps.googleusercontent.com';

/// Carries the verified Google identity from the login screen's "Continue
/// with Google" button through to the signup screen (new owner, no gym
/// yet) or claim screen (new member, not yet linked) — those screens
/// receive this as router `extra` and adapt their form (drop the
/// password field, show the already-verified email) instead of asking
/// the person to authenticate a second time.
class GoogleAuthContext {
  const GoogleAuthContext({
    required this.idToken,
    required this.email,
    this.fullName,
  });

  final String idToken;
  final String email;
  final String? fullName;
}

/// Raised for any real Google sign-in failure — never for the user
/// simply closing the account picker, which the caller treats as a
/// silent no-op (see signIn()'s null return).
class GoogleAuthFailure implements Exception {
  const GoogleAuthFailure(this.message);
  final String message;
}

/// Thin wrapper around the google_sign_in v7 API — centralizes the
/// exactly-once initialize() requirement and turns its exception codes
/// into the two outcomes every caller actually needs: cancelled (null)
/// or a real failure (GoogleAuthFailure with a message fit to show
/// directly).
class GoogleAuthService {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _googleWebClientId);
    _initialized = true;
  }

  /// Returns the signed-in Google account (with a verified ID token
  /// ready to send to the backend), or null if the person closed the
  /// account picker without choosing anything — that's not an error,
  /// just "try again later". Throws [GoogleAuthFailure] for every other
  /// outcome. Returns the whole account, not just the token, because a
  /// caller routing to signup/claim after an unrecognized Google
  /// identity needs the email (and ideally the name) to prefill those
  /// forms without asking the person to type something Google already
  /// told us.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      if (account.authentication.idToken == null) {
        throw const GoogleAuthFailure(
          "Couldn't get a sign-in token from Google. Please try again.",
        );
      }
      return account;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleAuthFailure(_messageFor(e));
    }
  }

  /// Clears Google's own remembered sign-in state so the next sign-in
  /// shows the account picker again instead of silently reusing the
  /// last account. Best-effort — logout must never fail because of this.
  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing meaningful to do with a failure here — the local
      // session is already being cleared regardless.
    }
  }

  String _messageFor(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return "Google sign-in isn't set up correctly. Please try again later.";
      case GoogleSignInExceptionCode.uiUnavailable:
      case GoogleSignInExceptionCode.interrupted:
        return "Couldn't complete Google sign-in. Please try again.";
      case GoogleSignInExceptionCode.canceled:
        // Unreachable — handled before this switch is reached — but
        // listed so this switch stays exhaustive as new codes are added.
        return "Couldn't complete Google sign-in. Please try again.";
      case GoogleSignInExceptionCode.userMismatch:
      case GoogleSignInExceptionCode.unknownError:
        return "Couldn't sign in with Google. Check your connection and try again.";
    }
  }
}

final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(),
);
