// lib/core/router/app_router.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/onboarding/screens/setup_screen.dart';
import '../../features/shell/screens/home_placeholder_screen.dart';

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Fires once when this provider is first read, not on every rebuild —
  // that's the trap the doc flagged. ref.listen here (not ref.watch)
  // means this provider body doesn't re-run when AuthState changes;
  // only the ValueNotifier ticks, which is what refreshListenable wants.
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
        // Session restore still in flight — park on splash, nowhere else.
        AuthUnknown() => loc == '/splash' ? null : '/splash',

        // No session — only /login is allowed.
        AuthUnauthenticated() => loc == '/login' ? null : '/login',

        AuthAuthenticated(:final user) => () {
            // Precedence matters: a staff member with a temp password
            // must hit /change-password even if their gym also needs
            // setup — checked first, unconditionally.
            if (user.mustChangePassword) {
              return loc == '/change-password' ? null : '/change-password';
            }
            if (user.gym.needsSetup) {
              return loc == '/setup' ? null : '/setup';
            }
            // Fully cleared — bounce off any gate/auth screen to home.
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
      GoRoute(path: '/splash', builder: (context, state) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      // Placeholder until app_shell.dart replaces this with the real
      // StatefulShellRoute + bottom nav.
      GoRoute(path: '/home', builder: (context, state) => const HomePlaceholderScreen()),
    ],
  );
});