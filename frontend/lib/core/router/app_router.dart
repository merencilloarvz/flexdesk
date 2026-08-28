import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/set_password_screen.dart';
import '../../features/onboarding/screens/setup_screen.dart';
import '../../features/shell/screens/home_placeholder_screen.dart';

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ValueNotifier<int>(0);
  final sub = ref.listen<AuthState>(authControllerProvider, (_, __) {
    refreshNotifier.value++;
  });
  ref.onDispose(() {
    sub.close();
    refreshNotifier.dispose();
  });

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      return switch (authState) {
        AuthUnknown() => loc == '/splash' ? null : '/splash',
        AuthUnauthenticated() => loc == '/login' ? null : '/login',
        AuthAuthenticated(:final user) => () {
          if (user.mustChangePassword) {
            return loc == '/change-password' ? null : '/change-password';
          }
          if (user.gym.needsSetup) {
            return loc == '/setup' ? null : '/setup';
          }
          if (loc == '/login' ||
              loc == '/splash' ||
              loc == '/change-password' ||
              loc == '/setup') {
            return '/home';
          }
          return null;
        }(),
      };
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) {
            final authState = ref.watch(authControllerProvider);
            final email = authState is AuthAuthenticated
                ? authState.user.email
                : '';
            return SetPasswordScreen(
              staffEmail: email,
              onVerifyTempPassword: (tempPassword, newPassword) async {
                try {
                  await ref
                      .read(authControllerProvider.notifier)
                      .completePasswordChange(tempPassword, newPassword);
                  return const TempPasswordResult.success();
                } on ApiException catch (e) {
                  return TempPasswordResult.failure(e.message);
                }
              },
              onPasswordSet: () {},
            );
          },
        ),
      ),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePlaceholderScreen(),
      ),
    ],
  );
});
