import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/qr_secret_storage.dart';
import '../../../core/api/token_storage.dart';
import '../../../core/db/app_database.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/auth_models.dart';
import '../services/google_auth_service.dart';

export '../data/auth_models.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  final bool restoreFailed;
  const AuthUnknown({this.restoreFailed = false});
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  final AuthUser user;
  const AuthAuthenticated(this.user);
}

// Thrown by logout() when there are offline-created members that haven't
// synced yet. The UI should catch this, warn the user, and call
// logout(force: true) if they confirm they want to proceed anyway.
class UnsyncedDataException implements Exception {
  final int count;
  const UnsyncedDataException(this.count);
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(tokenStorageProvider),
  ),
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnknown();

  Future<void> restore() async {
    try {
      final user = await ref.read(authRepositoryProvider).restoreSession();
      if (user != null) {
        state = AuthAuthenticated(user);
        // Tokens can silently rotate between sessions — re-register on
        // every app start while already authenticated, not just on a
        // fresh login/claim.
        // ignore: unawaited_futures
        ref.read(pushNotificationServiceProvider).registerToken();
        // Someone who was already logged in before push notifications
        // existed (or who denied the prompt back then and later enabled
        // it from Settings) would otherwise never get asked again by
        // requestPermissionOnce, which only tracks "have we ever asked".
        // This checks the real OS state on every app start instead.
        // ignore: unawaited_futures
        ref.read(pushNotificationServiceProvider).requestPermissionIfNotGranted();
      } else {
        state = const AuthUnauthenticated();
      }
    } on ApiException catch (e) {
      // Only an explicit rejection means the session is dead. A network failure
      // means we hold a valid refresh token and simply can't confirm the user yet.
      state = e.kind == ApiExceptionKind.network
          ? const AuthUnknown(restoreFailed: true)
          : const AuthUnauthenticated();
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    final user = await ref.read(authRepositoryProvider).login(email, password);
    state = AuthAuthenticated(user);
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).registerToken();
    // A no-op after this user's first login/claim ever — see
    // PushNotificationService.requestPermissionOnce. This is what makes
    // "ask after a staff member's first login" work: every later login
    // for the same account is a silent no-op.
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).requestPermissionOnce(user.id);
  }

  Future<void> signup({
    required String gymName,
    String? locationName,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final user = await ref
        .read(authRepositoryProvider)
        .signup(
          gymName: gymName,
          locationName: locationName,
          fullName: fullName,
          email: email,
          password: password,
        );
    state = AuthAuthenticated(user);
    // A newly-created owner account is a first-login moment too — same
    // reasoning as claim()/login().
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).registerToken();
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).requestPermissionOnce(user.id);
  }

  Future<void> claim({
    required String email,
    required String claimCode,
    required String password,
  }) async {
    final user = await ref
        .read(authRepositoryProvider)
        .claim(email: email, claimCode: claimCode, password: password);
    state = AuthAuthenticated(user);
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).registerToken();
    // Right after claim — the member has just done something deliberate
    // and has context for why notifications would help. See C1 in
    // FLEXDESK_PHASE4_PART_B_SPEC.md.
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).requestPermissionOnce(user.id);
  }

  /// Logs in (or links) an existing account via Google. Returns true on
  /// success; false means no account matches this Google identity at
  /// all, and the caller (login_screen.dart) routes to signup (owner)
  /// or claim (member) instead of showing an error.
  Future<bool> googleLogin({required String idToken}) async {
    final user = await ref
        .read(authRepositoryProvider)
        .googleLogin(idToken: idToken);
    if (user == null) return false;
    state = AuthAuthenticated(user);
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).registerToken();
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).requestPermissionOnce(user.id);
    return true;
  }

  Future<void> googleSignup({
    required String idToken,
    required String gymName,
    String? locationName,
  }) async {
    final user = await ref
        .read(authRepositoryProvider)
        .googleSignup(idToken: idToken, gymName: gymName, locationName: locationName);
    state = AuthAuthenticated(user);
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).registerToken();
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).requestPermissionOnce(user.id);
  }

  Future<void> googleClaim({
    required String idToken,
    required String claimCode,
  }) async {
    final user = await ref
        .read(authRepositoryProvider)
        .googleClaim(idToken: idToken, claimCode: claimCode);
    state = AuthAuthenticated(user);
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).registerToken();
    // ignore: unawaited_futures
    ref.read(pushNotificationServiceProvider).requestPermissionOnce(user.id);
  }

  Future<AuthUser> completePasswordChange(
    String currentPassword,
    String newPassword,
  ) async {
    return ref
        .read(authRepositoryProvider)
        .changePassword(currentPassword, newPassword);
  }

  void applyUser(AuthUser user) => state = AuthAuthenticated(user);

  /// Marks the welcome carousel seen and pushes the updated AuthUser
  /// into session state — the redirect in app_router.dart reads
  /// hasSeenOwnerWelcome off the CURRENT state on every navigation, so
  /// without this the very next redirect check would send the owner
  /// straight back to /welcome after they just left it.
  Future<void> markOwnerWelcomeSeen() async {
    final user = await ref.read(authRepositoryProvider).markOwnerWelcomeSeen();
    state = AuthAuthenticated(user);
  }

  Future<void> setClassesEnabled(bool value) async {
    final user = await ref
        .read(authApiProvider)
        .updateGymSettings(classesEnabled: value);
    state = AuthAuthenticated(user);
  }

  Future<void> logout({bool force = false}) async {
    final db = ref.read(dbProvider);
    final previousState = state;

    if (!force) {
      final dirtyCount =
          await db.countDirtyMembers() + await db.countDirtyCheckIns();
      if (dirtyCount > 0) {
        throw UnsyncedDataException(dirtyCount);
      }
    }

    // Must complete BEFORE the stored auth tokens are cleared below —
    // this DELETE call needs to go out authenticated, or the row is
    // left behind and the next person to log in on this device (a
    // shared front-desk tablet, a member's family phone) inherits the
    // previous account's notifications. See C2 in
    // FLEXDESK_PHASE4_PART_B_SPEC.md — deliberately awaited, not
    // fire-and-forget, unlike the other push calls in this file.
    await ref.read(pushNotificationServiceProvider).deleteToken();
    // Clears Google's own remembered account, not just our tokens — the
    // next sign-in must show the account picker again, not silently
    // reuse whoever was last signed in on this device.
    await ref.read(googleAuthServiceProvider).signOut();

    await db.clearAllData();
    await ref.read(authRepositoryProvider).logout();
    // Phase 3b B3 — the QR secret is keyed by member id in secure
    // storage, alongside the tokens; a device shared across accounts
    // must never let the next login read the previous member's secret.
    if (previousState is AuthAuthenticated) {
      await ref
          .read(qrSecretStorageProvider)
          .clear(previousState.user.id);
    }
    state = const AuthUnauthenticated();
  }

  void handleSessionExpired() {
    state = const AuthUnauthenticated();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
