import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/device_token_api.dart';
import 'push_notification_service.dart';

/// Shared by both Settings screens' "Send test notification" row —
/// fetches the notification types relevant to the caller's own role
/// (owners see owner-facing types, members see member-facing types; the
/// backend does the actual filtering) and, once one is picked, sends a
/// real sample of it to the caller's own devices only.
Future<void> showNotificationTestPicker(BuildContext context, WidgetRef ref) async {
  final api = ref.read(deviceTokenApiProvider);

  List<NotificationTestType> types;
  try {
    types = await api.fetchTestTypes();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't load notification types.")),
    );
    return;
  }
  if (!context.mounted) return;
  if (types.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No test notifications available for your role.'),
      ),
    );
    return;
  }

  final chosen = await showModalBottomSheet<NotificationTestType>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Send a test notification',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              "It's sent to your own devices only, with sample text.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          for (final t in types)
            ListTile(
              title: Text(t.label),
              onTap: () => Navigator.of(sheetContext).pop(t),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (chosen == null || !context.mounted) return;

  try {
    await api.sendTest(chosen.type);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${chosen.label} test sent.')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't send it. Check your connection.")),
    );
  }
}
