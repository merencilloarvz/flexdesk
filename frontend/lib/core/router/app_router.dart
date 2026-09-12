import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../features/community/screens/owners/announcement_list_screen.dart';
import '../../features/community/screens/owners/events_list_screen.dart';
import '../../features/members/screens/members_list_screen.dart';
import '../../features/members/screens/member_detail_screen.dart';
import '../../features/members/screens/member_create_screen.dart';
import '../../features/members/screens/manage_plans_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/role_picker_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/set_password_screen.dart';
import '../../features/auth/screens/claim_screen.dart';
import '../../features/auth/screens/no_gym_screen.dart';
import '../../features/settings/screens/staff_list_screen.dart';
import '../../features/settings/screens/staff_create_screen.dart';
import '../../features/dashboard/screens/home_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/checkin/check_in_screen.dart';
import '../../features/pos/screens/pos_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/members_home/screens/member_home_screen.dart';
import '../../features/members_home/screens/member_attendance_screen.dart';
import '../../features/members_home/screens/member_membership_screen.dart';
import '../../features/members_home/screens/member_settings_screen.dart';
import '../../features/scheduling/screens/member_schedule_screen.dart';
import '../../features/scheduling/screens/time_slot_list_screen.dart';
import '../../features/community/screens/member/community_screen.dart';
import '../../features/workout_guides/screens/workout_guides_screen.dart';
import '../../features/subscription/screens/subscribe_screen.dart';

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
    final gymId = authState is AuthAuthenticated
        ? authState.user.gym?.id ?? ''
        : '';
    return MembersListScreen(gymId: gymId);
  }
}

class _CheckInRoute extends ConsumerWidget {
  const _CheckInRoute({this.startOnWalkIn = false});
  final bool startOnWalkIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final gymId = authState is AuthAuthenticated
        ? authState.user.gym?.id ?? ''
        : '';
    return CheckInScreen(gymId: gymId, startOnWalkIn: startOnWalkIn);
  }
}

// Owner shell tabs — Modules replaces the old separate POS/Inventory
// tabs (neither is built, so one merged landing tab covers both);
// Settings is now its own tab instead of a gear button on Home.
// branchIndex must match this tab's position in the owner
// StatefulShellRoute's `branches` list below.
const _ownerTabs = [
  (icon: Icons.home_outlined, label: 'Home', branchIndex: 0),
  (icon: Icons.people_outline, label: 'Members', branchIndex: 1),
  (icon: Icons.how_to_reg_outlined, label: 'Check-In', branchIndex: 2),
  (icon: Icons.point_of_sale_outlined, label: 'POS', branchIndex: 3),
  (icon: Icons.settings_outlined, label: 'Settings', branchIndex: 4),
];

// Member shell tabs. The member StatefulShellRoute's `branches` list
// below is ALWAYS 5 branches (Home, Schedule, Community, Settings,
// Guides) — that list can't change shape at runtime. What changes is
// which of these tab entries get shown in the nav bar: when classes
// are disabled, the Schedule entry (branchIndex 1) is simply left out
// of the list passed to AppShell, so the branch still exists and its
// route is still reachable by a direct link, it's just not in the tab
// bar. branchIndex always refers to the fixed branch position, never
// to this list's own (variable) length or on-screen order — Guides
// sits at branchIndex 4 (added after Settings in the branches list)
// but is shown third in the tab bar, between Community and Schedule.
const _memberTabsWithSchedule = [
  (icon: Icons.home_outlined, label: 'Home', branchIndex: 0),
  (icon: Icons.groups_outlined, label: 'Community', branchIndex: 2),
  (icon: Icons.fitness_center_outlined, label: 'Guides', branchIndex: 4),
  (icon: Icons.calendar_month_outlined, label: 'Schedule', branchIndex: 1),
  (icon: Icons.settings_outlined, label: 'Settings', branchIndex: 3),
];
const _memberTabsBase = [
  (icon: Icons.home_outlined, label: 'Home', branchIndex: 0),
  (icon: Icons.groups_outlined, label: 'Community', branchIndex: 2),
  (icon: Icons.fitness_center_outlined, label: 'Guides', branchIndex: 4),
  (icon: Icons.settings_outlined, label: 'Settings', branchIndex: 3),
];

List<({IconData icon, String label, int branchIndex})> _memberTabsFor(
  bool classesEnabled,
) {
  return classesEnabled ? _memberTabsWithSchedule : _memberTabsBase;
}

final _homeNavigatorKey = GlobalKey<NavigatorState>();
final _membersNavigatorKey = GlobalKey<NavigatorState>();
final _checkinNavigatorKey = GlobalKey<NavigatorState>();
final _modulesNavigatorKey = GlobalKey<NavigatorState>();
final _ownerSettingsNavigatorKey = GlobalKey<NavigatorState>();

final _memberHomeNavigatorKey = GlobalKey<NavigatorState>();
final _memberSettingsNavigatorKey = GlobalKey<NavigatorState>();
final _memberScheduleNavigatorKey = GlobalKey<NavigatorState>();
final _memberCommunityNavigatorKey = GlobalKey<NavigatorState>();
final _memberGuidesNavigatorKey = GlobalKey<NavigatorState>();

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
        AuthUnauthenticated() =>
          (loc == '/role' ||
                  loc.startsWith('/login') ||
                  loc == '/signup' ||
                  loc == '/claim')
              ? null
              : '/role',
        AuthAuthenticated(:final user) => () {
          final isMember = user.accountType == 'member';
          final gym = user.gym;

          // No StaffProfile and no member_profile — a Django superuser,
          // or a profile that got removed. Every check below this point
          // reads gym.something, so this has to come first: not an
          // error screen, not a crash, a dead end with an exit.
          if (gym == null) {
            return loc == '/no-gym' ? null : '/no-gym';
          }

          if (isMember) {
            if (loc == '/role' ||
                loc == '/signup' ||
                loc.startsWith('/login') ||
                loc == '/claim' ||
                loc == '/splash' ||
                loc == '/change-password' ||
                loc == '/setup' ||
                loc == '/no-gym') {
              return '/member-home';
            }
            return null;
          }

          if (user.mustChangePassword) {
            return loc == '/change-password' ? null : '/change-password';
          }
          // Owner-only: a staff account signed in before the owner has
          // priced anything has no way to act on this screen (plan
          // writes are owner-only), so sending them here would just be
          // a second dead end.
          if (gym.needsSetup && user.role == UserRole.owner) {
            return loc == '/setup' ? null : '/setup';
          }
          if (gym.subscriptionBlocked) {
            return loc == '/subscribe' ? null : '/subscribe';
          }
          if (loc.startsWith('/settings/staff') &&
              user.role != UserRole.owner) {
            return '/settings';
          }
          if (loc == '/role' ||
              loc == '/signup' ||
              loc.startsWith('/login') ||
              loc == '/claim' ||
              loc == '/splash' ||
              loc == '/change-password' ||
              loc == '/setup' ||
              loc == '/no-gym') {
            return '/home';
          }
          // Deliberately NOT evicting '/subscribe' here the way '/setup'
          // is above: unlike setup, this screen is also reachable
          // voluntarily while merely trialing (not blocked), and an
          // unrelated background refresh elsewhere in the app (e.g.
          // home's periodic /auth/me/ poll) ticks this redirect too —
          // that must never yank someone off a screen they opened on
          // purpose. SubscribeScreen navigates itself away once its own
          // post-checkout refresh confirms the block is gone.
          return null;
        }(),
      };
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/role',
        builder: (context, state) => const RolePickerScreen(),
      ),
      GoRoute(
        path: '/login/:role',
        builder: (context, state) {
          final roleParam = state.pathParameters['role'];
          final role = roleParam == 'member' ? AuthRole.member : AuthRole.owner;
          return LoginScreen(role: role);
        },
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(path: '/claim', builder: (context, state) => const ClaimScreen()),
      GoRoute(
        path: '/no-gym',
        builder: (context, state) => const NoGymScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const _ChangePasswordRoute(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) {
          final authState = ref.read(authControllerProvider);
          final gymId = authState is AuthAuthenticated
              ? authState.user.gym?.id ?? ''
              : '';
          // Reuses ManagePlansScreen entirely rather than a second,
          // bespoke screen — see its firstRun doc comment.
          return ManagePlansScreen(gymId: gymId, firstRun: true);
        },
      ),
      GoRoute(
        path: '/subscribe',
        builder: (context, state) => const SubscribeScreen(),
      ),

      // /settings itself moved into the owner shell branch below —
      // only its sub-routes stay top-level, pushed on top of the shell.
      GoRoute(
        path: '/settings/staff',
        builder: (context, state) => const StaffListScreen(),
      ),
      GoRoute(
        path: '/settings/staff/create',
        builder: (context, state) => const StaffCreateScreen(),
      ),

      GoRoute(
        path: '/members/create',
        builder: (context, state) => const MemberCreateScreen(),
      ),
      GoRoute(
        path: '/plans/manage',
        builder: (context, state) {
          final authState = ref.read(authControllerProvider);
          final gymId = authState is AuthAuthenticated
              ? authState.user.gym?.id ?? ''
              : '';
          return ManagePlansScreen(gymId: gymId);
        },
      ),
      GoRoute(
        path: '/schedule',
        builder: (context, state) => const TimeSlotListScreen(),
      ),
      GoRoute(
        path: '/announcements',
        builder: (context, state) => const AnnouncementsListScreen(),
      ),
      GoRoute(
        path: '/events',
        builder: (context, state) => const EventsListScreen(),
      ),
      GoRoute(
        path: '/members/:id',
        builder: (context, state) =>
            MemberDetailScreen(memberId: state.pathParameters['id']!),
      ),

      GoRoute(
        path: '/me/attendance',
        builder: (context, state) => const MemberAttendanceScreen(),
      ),
      GoRoute(
        path: '/me/membership',
        builder: (context, state) => const MemberMembershipScreen(),
      ),

      // Owner shell — 5 tabs: Home, Members, Check-In, Modules, Settings.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          tabs: _ownerTabs,
          centerBranchIndex: 2, // Check-In stays the raised middle slot
        ),
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
                builder: (context, state) => _CheckInRoute(
                  startOnWalkIn: state.uri.queryParameters['tab'] == 'walkin',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _modulesNavigatorKey,
            routes: [
              GoRoute(
                path: '/modules',
                builder: (context, state) => const PosScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _ownerSettingsNavigatorKey,
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Member shell — Home, [Schedule], Community, Settings, Guides.
      // The Schedule branch always exists (see _memberTabsFor above);
      // only whether it appears in the tab bar depends on
      // classesEnabled. Guides always appears in the tab bar.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final authState = ref.read(authControllerProvider);
          final classesEnabled = authState is AuthAuthenticated
              ? authState.user.gym?.classesEnabled ?? false
              : false;
          return AppShell(
            navigationShell: navigationShell,
            tabs: _memberTabsFor(classesEnabled),
            centerBranchIndex: null, // no raised button on the member shell
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _memberHomeNavigatorKey,
            routes: [
              GoRoute(
                path: '/member-home',
                builder: (context, state) => const MemberHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _memberScheduleNavigatorKey,
            routes: [
              GoRoute(
                path: '/member-schedule',
                builder: (context, state) => const MemberScheduleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _memberCommunityNavigatorKey,
            routes: [
              GoRoute(
                path: '/member-community',
                builder: (context, state) => const CommunityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _memberSettingsNavigatorKey,
            routes: [
              GoRoute(
                path: '/member-settings',
                builder: (context, state) => const MemberSettingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _memberGuidesNavigatorKey,
            routes: [
              GoRoute(
                path: '/member-guides',
                builder: (context, state) => const WorkoutGuidesScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
