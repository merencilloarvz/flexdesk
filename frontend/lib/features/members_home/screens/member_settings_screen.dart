import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/notifications/notification_test_picker.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/qr_card_providers.dart';

// Update this if pubspec.yaml's version line changes. Not read
// dynamically — package_info_plus isn't a project dependency yet.
const _appVersion = '1.0.0';

class MemberSettingsScreen extends ConsumerWidget {
  const MemberSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;

    final notificationsEnabledAsync = ref.watch(notificationsEnabledProvider);
    final notificationsEnabled = notificationsEnabledAsync.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    user?.fullName.isNotEmpty == true
                        ? user!.fullName
                        : 'Member',
                  ),
                  subtitle: Text(user?.email ?? ''),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Gym'),
                  subtitle: Text(user?.gym?.name ?? ''),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh card'),
              subtitle: const Text(
                "If a staff member reset your card's code, tap this",
              ),
              onTap: () => _refreshCard(context, ref),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: Icon(
                notificationsEnabled == false
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
              ),
              title: const Text('Notifications'),
              subtitle: Text(
                notificationsEnabled == false
                    ? 'Off — tap to turn on in Android settings'
                    : 'Announcements, renewals & stock alerts',
              ),
              trailing: notificationsEnabled == null
                  ? null
                  : Text(
                      notificationsEnabled ? 'On' : 'Off',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
              onTap: () => _onTapNotifications(ref, notificationsEnabled),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Send test notification'),
              subtitle: const Text('Check that push notifications are working'),
              onTap: () => showNotificationTestPicker(context, ref),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: const Text('App version, licences & credits'),
              onTap: () => context.push('/about'),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'FlexDesk v$_appVersion',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Log out', style: TextStyle(color: Colors.red)),
              onTap: () => _confirmLogout(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  // B4 — the owner's confirmation after resetting a member's secret
  // tells them to come here. Fetches the new secret first and only
  // overwrites the cached one once that succeeds (QrCardRepository.
  // refreshSecret) — a failed or throttled fetch must never leave the
  // member with no working secret at all, so there's no upfront clear.
  Future<void> _refreshCard(BuildContext context, WidgetRef ref) async {
    final authState = ref.read(authControllerProvider);
    if (authState is! AuthAuthenticated) return;

    try {
      await ref
          .read(qrCardRepositoryProvider)
          .refreshSecret(authState.user.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Card refreshed.')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _onTapNotifications(WidgetRef ref, bool? enabled) async {
    if (enabled == false) {
      await ref
          .read(pushNotificationServiceProvider)
          .openSystemNotificationSettings();
    }
    ref.invalidate(notificationsEnabledProvider);
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to sign in again to continue."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // A member never creates dirty rows (no offline writes on this side
    // of the app), so countDirtyMembers()/countDirtyCheckIns() both
    // return 0 and UnsyncedDataException never fires here in practice —
    // but the call is left un-forced anyway, matching the owner flow,
    // rather than relying on that guarantee holding forever.
    await ref.read(authControllerProvider.notifier).logout();
  }
}
