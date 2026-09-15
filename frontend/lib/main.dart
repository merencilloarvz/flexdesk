import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_providers.dart';
import 'core/theme/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
    ref
        .read(pushNotificationServiceProvider)
        .initMessageHandling(onMessageTap: _handleNotificationTap);
  }

  // Routes a tap on a push notification — from the foreground banner,
  // from the OS tray (background), or from a cold start (terminated).
  // Part C's real destinations don't exist yet, so every type lands on
  // home for now; an unrecognized type must land there too rather than
  // crash or show a blank screen, since a future server version may
  // send a type this build doesn't know about. See E in
  // FLEXDESK_PHASE4_PART_B_SPEC.md.
  void _handleNotificationTap(Map<String, dynamic> data) {
    final authState = ref.read(authControllerProvider);
    final isMember = authState is AuthAuthenticated && authState.user.isMember;
    final homeRoute = isMember ? '/member-home' : '/home';
    final router = ref.read(appRouterProvider);

    switch (data['type']) {
      case 'renewal_reminder':
        // TODO(Part C): route to the member's membership screen (/me/membership).
        router.go(homeRoute);
      case 'announcement':
        // TODO(Part C): route to Community (/member-community).
        router.go(homeRoute);
      case 'out_of_stock':
      case 'low_stock_digest':
        // TODO(Part C): route to the inventory/stock screen.
        router.go(homeRoute);
      default:
        router.go(homeRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'FlexDesk',
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accentTeal),
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
