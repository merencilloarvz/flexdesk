import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_providers.dart';
import 'core/theme/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Must be registered before runApp — this is what lets FCM keep
  // delivering messages (and Android keep drawing the tray banner) while
  // the app is backgrounded or fully terminated.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: FlexDeskApp()));
}

class FlexDeskApp extends ConsumerStatefulWidget {
  const FlexDeskApp({super.key});
  @override
  ConsumerState<FlexDeskApp> createState() => _FlexDeskAppState();
}

class _FlexDeskAppState extends ConsumerState<FlexDeskApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider.notifier).restore());
    ref.read(pushNotificationServiceProvider).ensureNotificationChannel();
    ref
        .read(pushNotificationServiceProvider)
        .initMessageHandling(onMessageTap: _handleNotificationTap);
  }

  // Routes a tap on a push notification, whether it arrived while the
  // app was open, backgrounded, or fully terminated — all three show a
  // real system tray notification now (see PushNotificationService) and
  // route through here the same way. An unrecognized type (including the
  // "test" type from the Settings screen's test button) must land on
  // home rather than crash or show a blank screen, since a future server
  // version may send a type this build doesn't know about. See E in
  // FLEXDESK_PHASE4_PART_B_SPEC.md.
  void _handleNotificationTap(Map<String, dynamic> data) {
    final authState = ref.read(authControllerProvider);
    final isMember = authState is AuthAuthenticated && authState.user.isMember;
    final homeRoute = isMember ? '/member-home' : '/home';
    final router = ref.read(appRouterProvider);
    final id = data['id'] as String?;

    // Types and their string values come from backend's
    // core/notifications.TYPE_CATALOG — the single source of truth for
    // every type this build needs to route, used by real triggers and
    // by the Settings "Send test notification" picker alike.
    switch (data['type']) {
      case 'renewal':
        router.go('/me/membership');
      case 'announcement':
        router.go('/member-community');
        if (id != null && id.isNotEmpty) {
          openAnnouncementDetail(id);
        }
      case 'new_event':
        router.go('/member-community');
        if (id != null && id.isNotEmpty) {
          openMemberEventDetail(id);
        }
      case 'checkin':
        router.go('/member-home');
      case 'out_of_stock':
      case 'inventory':
        router.go('/modules');
        openInventory();
      case 'event_registration':
        router.go('/events');
        if (id != null && id.isNotEmpty) {
          openOwnerEventDetail(id);
        }
      case 'comment':
        // Comments notify gym staff, not members — always routes to the
        // owner side. There's no per-id "announcement detail" screen on
        // the owner side to deep-link into (only the list and an edit
        // form that expects an already-loaded Announcement), so an
        // announcement comment opens the list; an event comment can open
        // the real by-id event detail screen.
        if (data['target_type'] == 'event') {
          router.go('/events');
          if (id != null && id.isNotEmpty) {
            openOwnerEventDetail(id);
          }
        } else {
          router.go('/announcements');
        }
      case 'trial_ending':
        router.go('/subscribe');
      case 'daily_summary':
        router.go('/home');
      default:
        router.go(homeRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'FlexDesk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accentTeal),
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
