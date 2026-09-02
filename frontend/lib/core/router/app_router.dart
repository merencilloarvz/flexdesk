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
import '../../features/settings/screens/staff_list_screen.dart';
import '../../features/settings/screens/staff_create_screen.dart';
import '../../features/dashboard/screens/home_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/checkin/check_in_screen.dart';
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

class _MembersRoute extends ConsumerWidget {
  const _MembersRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final gymId = authState is AuthAuthenticated ? authState.user.gym.id : '';
    return MembersListScreen(gymId: gymId);
  }
}

class _CheckInRoute extends ConsumerWidget {
  const _CheckInRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final gymId = authState is AuthAuthenticated ? authState.user.gym.id : '';
    return CheckInScreen(gymId: gymId);
  }
}

// One key per tab, required by StatefulShellRoute so each branch keeps
// its own independent Navigator (and therefore its own state/scroll
// position) instead of being torn down on every tab switch.
final _homeNavigatorKey = GlobalKey<NavigatorState>();
final _membersNavigatorKey = GlobalKey<NavigatorState>();
final _checkinNavigatorKey = GlobalKey<NavigatorState>();
final _posNavigatorKey = GlobalKey<NavigatorState>();
final _inventoryNavigatorKey = GlobalKey<NavigatorState>();

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
          // Belt-and-braces guard: the Settings screen already hides the
          // entry point from staff, but this stops a deep link from
          // reaching the screen at all.
          if (loc.startsWith('/settings/staff') &&
              user.role != UserRole.owner) {
            return '/settings';
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
      // not a bottom-nav tab — so it stays outside the shell and
      // shows without the pill nav underneath it.
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/staff',
        builder: (context, state) => const StaffListScreen(),
      ),
      GoRoute(
        path: '/settings/staff/create',
        builder: (context, state) => const StaffCreateScreen(),
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
      // StatefulShellRoute.indexedStack keeps each tab's own Navigator
      // (and its state/scroll position) alive in the background when
      // you switch tabs, instead of rebuilding the branch from scratch
      // like a plain ShellRoute does.
      //
      // Add any future tab as a new StatefulShellBranch below, not as
      // a standalone route above.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _membersNavigatorKey,
            routes: [
              GoRoute(
                path: '/members',
                builder: (context, state) => const _MembersRoute(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _checkinNavigatorKey,
            routes: [
              GoRoute(
                path: '/checkin',
                builder: (context, state) => const _CheckInRoute(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _posNavigatorKey,
            routes: [
              GoRoute(
                path: '/pos',
                builder: (context, state) => const PosPlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _inventoryNavigatorKey,
            routes: [
              GoRoute(
                path: '/inventory',
                builder: (context, state) => const InventoryPlaceholderScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
