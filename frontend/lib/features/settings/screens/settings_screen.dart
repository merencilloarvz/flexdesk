import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_test_picker.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../pos/screens/inventory_screen.dart';
import '../providers/staff_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final email = authState is AuthAuthenticated ? authState.user.email : '';
    final isOwner =
        authState is AuthAuthenticated && authState.user.role == UserRole.owner;
    final classesEnabled =
        authState is AuthAuthenticated &&
        (authState.user.gym?.classesEnabled ?? false);
    final subscriptionStatus = authState is AuthAuthenticated
        ? authState.user.gym?.subscriptionStatus
        : null;

    final staffAsync = isOwner ? ref.watch(staffListProvider) : null;
    final activeStaffCount = staffAsync?.asData?.value
        .where((s) => s.isActive)
        .length;

    final notificationsEnabledAsync = ref.watch(notificationsEnabledProvider);
    final notificationsEnabled = notificationsEnabledAsync.asData?.value;

    Future<void> onTapNotifications() async {
      if (notificationsEnabled == false) {
        await ref
            .read(pushNotificationServiceProvider)
            .openSystemNotificationSettings();
      }
      ref.invalidate(notificationsEnabledProvider);
    }

    Future<void> onToggleClasses(bool value) async {
      try {
        await ref
            .read(authControllerProvider.notifier)
            .setClassesEnabled(value);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't update that setting. Check your connection.",
            ),
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentTealBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 20,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.accentTeal,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Signed in',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (isOwner) ...[
              const SizedBox(height: 20),
              const _SectionLabel('GYM'),
              const SizedBox(height: 8),
              _SettingsSwitchRow(
                icon: Icons.calendar_month_outlined,
                title: 'Classes and bookings',
                subtitle:
                    'Turn this on if your gym runs scheduled classes. '
                    'Most gyms leave this off.',
                value: classesEnabled,
                onChanged: onToggleClasses,
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                icon: Icons.sell_outlined,
                title: 'Membership plans',
                subtitle: 'Pricing & tiers',
                onTap: () => context.push('/plans/manage'),
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                icon: Icons.inventory_2_outlined,
                title: 'Store items',
                subtitle: 'Products you sell at the counter',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InventoryScreen()),
                ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('ACCESS & ADMINISTRATION'),
              const SizedBox(height: 8),
              _SettingsRow(
                icon: Icons.badge_outlined,
                title: 'Staff',
                subtitle: 'Manage staff accounts & roles',
                badge: activeStaffCount != null
                    ? '$activeStaffCount Active'
                    : null,
                onTap: () => context.push('/settings/staff'),
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                icon: Icons.credit_card_outlined,
                title: 'Subscription',
                subtitle: subscriptionStatus == 'trialing'
                    ? 'Free trial'
                    : 'Manage your FlexDesk plan',
                badge: subscriptionStatus == 'trialing' ? 'Trial' : null,
                onTap: () => context.push('/subscribe'),
              ),
            ],

            const SizedBox(height: 20),
            const _SectionLabel('NOTIFICATIONS'),
            const SizedBox(height: 8),
            _SettingsRow(
              icon: notificationsEnabled == false
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: notificationsEnabled == false
                  ? 'Off — tap to turn on in Android settings'
                  : 'Announcements, renewals & stock alerts',
              badge: notificationsEnabled == null
                  ? null
                  : (notificationsEnabled ? 'On' : 'Off'),
              onTap: onTapNotifications,
            ),
            const SizedBox(height: 8),
            _SettingsRow(
              icon: Icons.send_outlined,
              title: 'Send test notification',
              subtitle: 'Check that push notifications are working',
              onTap: () => showNotificationTestPicker(context, ref),
            ),

            const SizedBox(height: 20),
            _SettingsRow(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'App version, licences & credits',
              onTap: () => context.push('/about'),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, ref),
                icon: const Icon(
                  Icons.logout,
                  size: 18,
                  color: AppColors.errorText,
                ),
                label: const Text('Log out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.errorText,
                  backgroundColor: AppColors.cardBg,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again to continue.'),
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

    await _performLogout(context, ref, force: false);
  }

  Future<void> _performLogout(
    BuildContext context,
    WidgetRef ref, {
    required bool force,
  }) async {
    try {
      await ref.read(authControllerProvider.notifier).logout(force: force);
    } on UnsyncedDataException catch (e) {
      if (!context.mounted) return;

      final proceedAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsynced records'),
          content: Text(
            '${e.count} record${e.count == 1 ? '' : 's'} '
            "haven't synced yet. Connect to wifi and try again, "
            'or log out anyway and lose that data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out anyway'),
            ),
          ],
        ),
      );

      if (proceedAnyway == true && context.mounted) {
        await _performLogout(context, ref, force: true);
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.accentTeal,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentTealBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppColors.accentTeal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentTealBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentTeal,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same card shape as _SettingsRow, but for a boolean setting rather
/// than a navigation link — a trailing Switch instead of a chevron, and
/// no onTap on the whole row (only the switch itself is interactive, so
/// a stray tap on the text doesn't silently flip a gym-wide setting).
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentTealBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.accentTeal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accentTeal,
          ),
        ],
      ),
    );
  }
}
