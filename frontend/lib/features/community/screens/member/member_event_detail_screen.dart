import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import 'event_leaderboard_screen.dart';

class MemberEventDetailScreen extends ConsumerStatefulWidget {
  const MemberEventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<MemberEventDetailScreen> createState() =>
      _MemberEventDetailScreenState();
}

class _MemberEventDetailScreenState
    extends ConsumerState<MemberEventDetailScreen> {
  Event? _event;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final event = await ref
          .read(communityRepositoryProvider)
          .fetchEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.kind == ApiExceptionKind.network
            ? 'You need an internet connection to view this event.'
            : e.message;
      });
    }
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    final result = await ref
        .read(communityRepositoryProvider)
        .register(widget.eventId);
    if (!mounted) return;
    if (result.outcome != EventActionOutcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? "Couldn't register.")),
      );
    }
    setState(() => _busy = false);
    // Any outcome re-fetches — the screen was already stale the moment
    // it rendered.
    await _load();
  }

  Future<void> _unregister() async {
    final event = _event;
    if (event?.myRegistration == null) return;
    final isPaid = event!.myRegistration!.paymentStatus == 'paid';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unregister?'),
        content: Text(
          isPaid
              ? 'You already paid for this event. Refunds are handled in '
                    'person at the gym — this only cancels your registration.'
              : 'Cancel your registration for ${event.title}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unregister'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await ref
        .read(communityRepositoryProvider)
        .unregister(widget.eventId);
    if (!mounted) return;
    if (result.outcome != EventActionOutcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? "Couldn't unregister.")),
      );
    } else if (result.message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message!)));
    }
    setState(() => _busy = false);
    await _load();
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final event = _event;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(event?.title ?? 'Event')),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!),
                ),
              )
            : event == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    if (event.isCanceled)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.errorBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'This event has been cancelled.',
                          style: TextStyle(
                            color: AppColors.errorText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      '${_months[event.eventDate.month - 1]} ${event.eventDate.day}, ${event.eventDate.year}'
                      '${event.startTime != null ? " · ${event.startTime!.substring(0, 5)}" : ""}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (event.locationText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.locationText,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '₱${(event.feeCentavos / 100).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (event.capacity != null && event.spotsLeft != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${event.spotsLeft} spots left',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'About',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.description,
                        style: const TextStyle(color: AppColors.subtle),
                      ),
                    ],
                    if (event.prizeDescription.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Prizes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.prizeDescription,
                        style: const TextStyle(color: AppColors.subtle),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildActionButton(event),
                    if (event.eventDate.isBefore(DateTime.now())) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventLeaderboardScreen(
                                eventId: event.id,
                                eventTitle: event.title,
                              ),
                            ),
                          ),
                          child: const Text('View Results'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActionButton(Event event) {
    if (event.isCanceled) return const SizedBox.shrink();
    final reg = event.myRegistration;
    if (_busy) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (reg != null) {
      return SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _unregister,
          child: Text(
            reg.paymentStatus == 'paid'
                ? 'Registered · Paid — Unregister'
                : 'Registered · Unregister',
          ),
        ),
      );
    }
    final full = event.capacity != null && (event.spotsLeft ?? 1) <= 0;
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: full ? null : _register,
        style: FilledButton.styleFrom(backgroundColor: AppColors.accentTeal),
        child: Text(full ? 'Full' : 'Register'),
      ),
    );
  }
}
