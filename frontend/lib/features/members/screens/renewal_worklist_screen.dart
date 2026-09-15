import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/renewals_repository.dart';
import '../providers/members_providers.dart';
import '../providers/renewals_providers.dart';
import 'member_detail_screen.dart' show RenewSheet;

/// Phase 5 Part B — the owner's renewal worklist. Reachable from Home
/// (S1). Never caches in Drift (B4) — every open is a live fetch, and
/// "Mark as contacted" waits for the server and re-fetches rather than
/// patching a row locally (standing rule 12 — no optimistic UI here,
/// since two staff marking the same person at once has to resolve on
/// the server, not on two phones that each think they won, per S5).
class RenewalWorklistScreen extends ConsumerStatefulWidget {
  const RenewalWorklistScreen({super.key});

  @override
  ConsumerState<RenewalWorklistScreen> createState() =>
      _RenewalWorklistScreenState();
}

class _RenewalWorklistScreenState
    extends ConsumerState<RenewalWorklistScreen> {
  List<ExpiringMember>? _rows;
  bool _loading = true;
  bool _offline = false;
  String? _errorMessage;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _gymId() {
    final authState = ref.read(authControllerProvider);
    return authState is AuthAuthenticated ? authState.user.gym?.id : null;
  }

  /// [showSpinner] false is for a post-write refetch (after Mark as
  /// contacted or Renew): the existing rows stay on screen while this
  /// runs — _submitting already disables the row buttons for that
  /// window — instead of blanking the whole list to a spinner to
  /// confirm one row. The row itself still only changes once this
  /// fetch actually returns; nothing here is optimistic.
  Future<void> _load({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _offline = false;
      _errorMessage = null;
    });
    try {
      final rows = await ref.read(renewalsRepositoryProvider).fetchExpiring();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });

      // Home's own count (dashboardStatsProvider) is computed from the
      // locally-cached member list, fetched independently of this
      // screen — the two can disagree whenever a day boundary, a
      // renewal, or a reminder on another device has moved someone in
      // or out of the window since Home's own last sync. A bare
      // ref.invalidate(visibleMembersProvider(gymId)) wouldn't fix
      // that: it's a StreamProvider over a Drift .watch() query, which
      // is already live/reactive on its own — invalidating it just
      // re-subscribes to the same local data, it doesn't pull
      // anything from the server. refreshMembers(gymId) is the actual
      // network refetch (the same call home_screen.dart's own
      // _refresh() makes); Drift's reactivity means visibleMembersProvider
      // picks up the result automatically once it lands, no explicit
      // invalidate needed. Fire-and-forget and best-effort — this
      // screen's own state must never depend on it.
      final gymId = _gymId();
      if (gymId != null) {
        // ignore: unawaited_futures
        ref.read(membersRepositoryProvider).refreshMembers(gymId).catchError((
          _,
        ) {});
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!showSpinner) {
        // A background post-write refetch failed — keep the existing
        // (now possibly slightly stale) rows on screen rather than
        // replacing them with the offline/error state; losing an
        // already-loaded list over a transient blip is worse than a
        // stale one, and the write itself already succeeded.
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.kind == ApiExceptionKind.network
                  ? "Couldn't refresh — check your connection."
                  : e.message,
            ),
          ),
        );
        return;
      }
      setState(() {
        _loading = false;
        if (e.kind == ApiExceptionKind.network) {
          _offline = true;
        } else {
          _errorMessage = e.message;
        }
      });
    }
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      // Best-effort — no dialer app, or the platform refused. Nothing
      // sensible to show; the phone number is still visible on the row.
    }
  }

  Future<void> _markContacted(ExpiringMember row) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _ContactedDialog(memberName: row.fullName),
    );
    if (note == null || !mounted) return; // cancelled

    setState(() => _submitting = true);
    try {
      await ref
          .read(renewalsRepositoryProvider)
          .markContacted(row.id, note: note.isEmpty ? null : note);
      // No local patch — reload from the server so the row only
      // changes once the write has actually landed (standing rule 12).
      // showSpinner: false — leave the list visible while this runs.
      await _load(showSpinner: false);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _renew(ExpiringMember row, String gymId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        // B2 — the existing renewal flow, unchanged. One renewal code
        // path, not two.
        child: RenewSheet(memberId: row.id, gymId: gymId),
      ),
    );
    if (!mounted) return;
    // Same _submitting gate as Mark as contacted, for the same reason
    // — the buttons stay disabled for the duration of this background
    // refetch too, not just the modal-open window.
    setState(() => _submitting = true);
    try {
      // Renewing moves current_end_date out of the window, so the
      // member should simply be gone from the next fetch — same
      // "reload, don't patch" rule as marking contacted, same
      // reduced-disruption refetch.
      await _load(showSpinner: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final gymId = authState is AuthAuthenticated
        ? authState.user.gym?.id ?? ''
        : '';

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Renewals',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(child: _body(gymId)),
    );
  }

  Widget _body(String gymId) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_offline) {
      // Same shape as the QR scanner's/digital card's offline state —
      // icon, plain message, Retry. This screen is a live read of
      // shared state and Mark as contacted is a contended write, so
      // there's no cached fallback to show instead (B3).
      return _MessageState(
        icon: Icons.wifi_off_rounded,
        message: 'Renewals needs a connection.',
        onRetry: _load,
      );
    }
    if (_errorMessage != null) {
      return _MessageState(
        icon: Icons.error_outline,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    final rows = _rows ?? const <ExpiringMember>[];
    if (rows.isEmpty) {
      // Plain and calm — not a celebration, not an error (B3).
      return const Center(
        child: Text(
          'Nobody is due for a renewal call right now.',
          style: TextStyle(color: AppColors.subtle),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accentTeal,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = rows[index];
          return _WorklistRow(
            row: row,
            onCall: _submitting ? null : () => _call(row.phone),
            onMarkContacted: _submitting ? null : () => _markContacted(row),
            onRenew: _submitting ? null : () => _renew(row, gymId),
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.subtle),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactedDialog extends StatefulWidget {
  const _ContactedDialog({required this.memberName});

  final String memberName;

  @override
  State<_ContactedDialog> createState() => _ContactedDialogState();
}

class _ContactedDialogState extends State<_ContactedDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mark ${widget.memberName} as contacted?'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(hintText: 'Note (optional)'),
        maxLines: 2,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentTeal),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _WorklistRow extends StatelessWidget {
  const _WorklistRow({
    required this.row,
    required this.onCall,
    required this.onMarkContacted,
    required this.onRenew,
  });

  final ExpiringMember row;
  final VoidCallback? onCall;
  final VoidCallback? onMarkContacted;
  final VoidCallback? onRenew;

  @override
  Widget build(BuildContext context) {
    // B1 — contacted rows render visibly muted. The point of this
    // screen is "who still needs a call", not a log of everyone.
    final muted = row.hasReminder;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: muted ? AppColors.fieldBg : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.fullName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: muted ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    if (row.memberCode.isNotEmpty)
                      Text(
                        row.memberCode,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DaysBadge(days: row.daysRemaining, muted: muted),
            ],
          ),
          if ((row.currentPlanCategory ?? '').isNotEmpty ||
              row.phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if ((row.currentPlanCategory ?? '').isNotEmpty)
                  row.currentPlanCategory!,
                if (row.phone.isNotEmpty) row.phone,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          if (row.hasReminder) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.reminderContactedBy != null
                        ? 'Contacted by ${row.reminderContactedBy}, '
                              '${_relativeDay(row.reminderContactedAt!)}'
                        : 'Contacted ${_relativeDay(row.reminderContactedAt!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (row.phone.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined, size: 15),
                    label: const Text('Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentTeal,
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  // Still tappable even when already contacted — A3:
                  // a second call on a different day is a real second
                  // contact, not a no-op.
                  onPressed: onMarkContacted,
                  icon: const Icon(Icons.check_outlined, size: 15),
                  label: const Text('Contacted'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentTeal,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onRenew,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentTeal,
                  ),
                  child: const Text('Renew'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DaysBadge extends StatelessWidget {
  const _DaysBadge({required this.days, required this.muted});

  final int? days;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final label = days == null
        ? '—'
        : days == 0
        ? 'Today'
        : '$days ${days == 1 ? 'day' : 'days'}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted ? AppColors.disabledBg : AppColors.expiringIcon,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: muted ? AppColors.disabledLabel : AppColors.expiringBg,
        ),
      ),
    );
  }
}

String _relativeDay(DateTime utcInstant) {
  final local = utcInstant.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'yesterday';
  return DateFormat('MMM d').format(local);
}
