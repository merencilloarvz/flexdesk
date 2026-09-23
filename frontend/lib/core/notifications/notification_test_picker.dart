import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/device_token_api.dart';
import 'push_notification_service.dart';

/// Turns a failed request into a message worth reading instead of a
/// generic "something went wrong" — in particular, a 404/405 on
/// /devices/test/ means the app is talking to a server that doesn't
/// have this endpoint's current contract yet (e.g. this build's backend
/// changes haven't been deployed), which is a very different problem
/// from "no internet" and shouldn't look the same in the UI.
String _describeError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 404 || status == 405) {
      return "The server doesn't support this yet — it may be running "
          'an older version of the backend.';
    }
    if (status == 401) {
      return 'Your session expired. Log in again and retry.';
    }
    if (status != null) {
      return 'Server error ($status). Try again in a moment.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return "Couldn't reach the server. Check your connection.";
    }
  }
  return 'Something went wrong: $error';
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(_describeError(error)),
      duration: const Duration(seconds: 6),
    ),
  );
}

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
  } catch (e) {
    if (!context.mounted) return;
    _showError(context, e);
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
    final result = await api.sendTest(chosen.type);
    if (!context.mounted) return;
    if (result.sent == 0) {
      // The request succeeded, but FCM never reached a device — most
      // often no device token is registered yet (permission never
      // granted, or the app was never opened after granting it). Worth
      // saying explicitly rather than claiming success when nothing
      // was actually delivered.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sent, but no device received it — check that notification '
            'permission is on for this app.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${chosen.label} test sent.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    _showError(context, e);
  }
}
