import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_providers.dart';

void main() {
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
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'FlexDesk',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
