import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../features/members/screens/members_list_screen.dart';
import '../../features/members/screens/member_detail_screen.dart';
import '../../features/members/screens/member_create_screen.dart';
import '../../features/members/screens/manage_plans_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/set_password_screen.dart';
import '../../features/onboarding/screens/setup_screen.dart';
import '../../features/shell/screens/home_placeholder_screen.dart';
import '../../features/shell/screens/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/checkin/checkin_placeholder_screen.dart';
import '../../features/inventory/inventory_placeholder_screen.dart';
import '../../features/pos/pos_placeholder_screen.dart';

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final restoreFailed = authState is AuthUnknown && authState.restoreFailed;

    return Scaffold(
      body: Center(
        child: restoreFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Can't reach the server"),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).restore(),
                    child: const Text('Retry'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _ChangePasswordRoute extends ConsumerStatefulWidget {
  const _ChangePasswordRoute();

  @override
  ConsumerState<_ChangePasswordRoute> createState() =>
      _ChangePasswordRouteState();
}

class _ChangePasswordRouteState extends ConsumerState<_ChangePasswordRoute> {
  AuthUser? _pendingUser;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final email = authState is AuthAuthenticated ? authState.user.email : '';

    return SetPasswordScreen(
      staffEmail: email,
      onVerifyTempPassword: (tempPassword, newPassword) async {
        try {
          final user = await ref
              .read(authControllerProvider.notifier)
              .completePasswordChange(tempPassword, newPassword);
          _pendingUser = user;
          return const TempPasswordResult.success();
        } on ApiException catch (e) {
          return TempPasswordResult.failure(e.message);
        }
      },
      onPasswordSet: () {
        final user = _pendingUser;
        if (user != null) {
          ref.read(authControllerProvider.notifier).applyUser(user);
        }
      },
    );
  }
}

// TODO: assumes `user.gym` has an `id` field, matching the pattern already
// used for `user.gym.needsSetup` below. If the field is named differently,
// adjust the one line inside build().
class _MembersRoute extends ConsumerWidget {
  const _MembersRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final gymId = authState is AuthAuthenticated ? authState.user.gym.id : '';
    return MembersListScreen(gymId: gymId);
  }
}

final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ValueNotifier<int>(0);
  final sub = ref.listen<AuthState>(authControllerProvider, (_, _) {
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
        builder: (context, state) => const _ChangePasswordRoute(),
      ),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),

      // Reached via the persistent gear icon in AppShell (context.push),
      // not a bottom-nav tab — so it stays outside the ShellRoute and
      // shows without the pill nav underneath it.
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // Detail/create/manage flows stay as plain top-level routes, same
      // as before — no bottom nav under these either.
      GoRoute(
        path: '/members/create',
        builder: (context, state) => const MemberCreateScreen(),
      ),
      GoRoute(
        path: '/plans/manage',
        builder: (context, state) {
          final authState = ref.read(authControllerProvider);
          final gymId = authState is AuthAuthenticated
              ? authState.user.gym.id
              : '';
          return ManagePlansScreen(gymId: gymId);
        },
      ),
      GoRoute(
        path: '/members/:id',
        builder: (context, state) =>
            MemberDetailScreen(memberId: state.pathParameters['id']!),
      ),

      // Main tabs, wrapped in the persistent shell (floating pill nav).
      // Add any future top-level screen as a sibling GoRoute inside this
      // ShellRoute, not as a standalone route above.
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomePlaceholderScreen(),
          ),
          GoRoute(
            path: '/members',
            builder: (context, state) => const _MembersRoute(),
          ),
          GoRoute(
            path: '/checkin',
            builder: (context, state) => const CheckInPlaceholderScreen(),
          ),
          GoRoute(
            path: '/pos',
            builder: (context, state) => const PosPlaceholderScreen(),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryPlaceholderScreen(),
          ),
        ],
      ),
    ],
  );
});
