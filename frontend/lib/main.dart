import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_providers.dart';
import 'core/theme/colors.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accentTeal),
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
