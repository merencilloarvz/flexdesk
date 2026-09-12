import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';

/// Where the router sends any authenticated account with no gym at all
/// (gym == null) — today that's a Django superuser logging in, or a
/// profile that got removed. Not an error screen, not a crash: a dead
/// end with an exit. There is nothing else this account can do in the
/// app, so the only action offered is logging out.
class NoGymScreen extends ConsumerStatefulWidget {
  const NoGymScreen({super.key});

  @override
  ConsumerState<NoGymScreen> createState() => _NoGymScreenState();
}

class _NoGymScreenState extends ConsumerState<NoGymScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).logout(force: true);
    } catch (_) {
      // logout() clears the local session unconditionally before the
      // fire-and-forget server call — this should never throw, but if
      // it somehow does, there's still nothing else useful to do here.
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.person_off_outlined,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                const Text(
                  "This account isn't linked to a gym",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact your gym owner to get set up, or sign in with a '
                  'different account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loggingOut ? null : _logout,
                  child: _loggingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
