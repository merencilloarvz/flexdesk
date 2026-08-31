import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/token_storage.dart';
import '../../../core/db/app_database.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/auth_models.dart';

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
      state = user != null
          ? AuthAuthenticated(user)
          : const AuthUnauthenticated();
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

  Future<void> logout({bool force = false}) async {
    final db = ref.read(dbProvider);

    if (!force) {
      final dirtyCount = await db.countDirtyMembers();
      if (dirtyCount > 0) {
        throw UnsyncedDataException(dirtyCount);
      }
    }

    await db.clearAllData();
    await ref.read(authRepositoryProvider).logout();
    state = const AuthUnauthenticated();
  }

  void handleSessionExpired() {
    state = const AuthUnauthenticated();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
