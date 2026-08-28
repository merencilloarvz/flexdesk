import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/token_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/auth_models.dart';

export '../data/auth_models.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  final AuthUser user;
  const AuthAuthenticated(this.user);
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
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    final user = await ref.read(authRepositoryProvider).login(email, password);
    state = AuthAuthenticated(user);
  }

  Future<void> completePasswordChange(
    String oldPassword,
    String newPassword,
  ) async {
    final user = await ref
        .read(authRepositoryProvider)
        .changePassword(oldPassword, newPassword);
    Future.delayed(const Duration(milliseconds: 900), () {
      state = AuthAuthenticated(user);
    });
  }

  Future<void> logout() async {
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
