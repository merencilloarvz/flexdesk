import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import '../../widgets/comments_section.dart';
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
  bool _bookmarked = false;

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

  void _showGuidelines(String guidelines) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guidelines',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              guidelines,
              style: const TextStyle(color: AppColors.subtle, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  void _openLeaderboard(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EventLeaderboardScreen(eventId: event.id, eventTitle: event.title),
      ),
    );
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

  String _dateLabel(Event event) {
    final d = event.eventDate;
    var label = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    if (event.startTime != null) label += ' · ${event.startTime!.substring(0, 5)}';
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final authState = ref.watch(authControllerProvider);
    final gymName = authState is AuthAuthenticated
        ? authState.user.gym?.name
        : null;
    final resultsAvailable =
        event != null && event.eventDate.isBefore(GymTime.today());

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Event Details',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            color: resultsAvailable ? AppColors.accentTeal : AppColors.muted,
            onPressed: event == null
                ? null
                : () {
                    if (resultsAvailable) {
                      _openLeaderboard(event);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Results aren't available yet."),
                        ),
                      );
                    }
                  },
          ),
          IconButton(
            icon: Icon(
              _bookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: _bookmarked ? AppColors.accentTeal : AppColors.ink,
            ),
            onPressed: event == null
                ? null
                : () => setState(() => _bookmarked = !_bookmarked),
          ),
        ],
      ),
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
                color: AppColors.accentTeal,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    if (event.isCanceled) ...[
                      Container(
                        width: double.infinity,
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
                      const SizedBox(height: 12),
                    ] else
                      _StatusBanner(event: event),
                    const SizedBox(height: 16),

                    if (gymName != null) ...[
                      Text(
                        event.locationText.isNotEmpty
                            ? '${gymName.toUpperCase()} • ${event.locationText}'
                            : gymName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        event.description,
                        style: const TextStyle(
                          color: AppColors.subtle,
                          height: 1.4,
                        ),
                      ),
                    ],

                    if (event.guidelines != null &&
                        event.guidelines!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => _showGuidelines(event.guidelines!),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.rule_outlined,
                                size: 18,
                                color: AppColors.accentTeal,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Guidelines',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accentTeal,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AppColors.accentTeal,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.calendar_today_rounded,
                            label: 'Date & Schedule',
                            value: _dateLabel(event),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.place_outlined,
                            label: 'Venue',
                            value: event.locationText.isNotEmpty
                                ? event.locationText
                                : 'TBA',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.confirmation_num_outlined,
                            label: 'Registration Fee',
                            value: event.feeCentavos > 0
                                ? '₱${(event.feeCentavos / 100).toStringAsFixed(0)}'
                                : 'Free',
                            valueColor: AppColors.accentTeal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.emoji_events_outlined,
                            label: 'Award Pool',
                            value: event.prizeDescription.isNotEmpty
                                ? event.prizeDescription
                                : 'No prize listed',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    _RegistrantsRow(event: event),

                    const SizedBox(height: 24),
                    CommentsSection(
                      itemType: CommunityItemType.event,
                      itemId: event.id,
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: event == null || event.isCanceled
          ? null
          : _BottomBar(
              event: event,
              busy: _busy,
              onRegister: _register,
              onUnregister: _unregister,
            ),
    );
  }
}

/// The event's start_time, on its own event_date, as a gym-local
/// [DateTime] comparable against [GymTime.now]. Caller must check
/// `event.startTime != null` first.
DateTime _startMoment(Event event) {
  final t = event.startTime!.split(':');
  return DateTime(
    event.eventDate.year,
    event.eventDate.month,
    event.eventDate.day,
    int.parse(t[0]),
    int.parse(t[1]),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    final today = GymTime.today();
    final isPastDay = event.eventDate.isBefore(today);
    // A date-only comparison never flips for the rest of the event's own
    // day — a 6pm event still reads "Registration Open" at 11pm without
    // this. Only meaningful when a start_time exists; without one there's
    // no time-of-day to compare against, so it falls back to the old
    // date-only behavior.
    final startedToday = !isPastDay &&
        !event.eventDate.isAfter(today) &&
        event.startTime != null &&
        !GymTime.now().isBefore(_startMoment(event));
    final full = event.capacity != null && (event.spotsLeft ?? 1) <= 0;
    final statusText = switch (true) {
      _ when isPastDay => 'Event Completed',
      _ when startedToday => 'Event In Progress',
      _ when full => 'Registration Closed',
      _ => 'Registration Open',
    };
    final limited = !isPastDay &&
        !startedToday &&
        !full &&
        event.capacity != null &&
        event.spotsLeft != null &&
        event.spotsLeft! <= 5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.linkGreen,
            ),
          ),
          if (limited) ...[
            const Spacer(),
            Text(
              'Only ${event.spotsLeft} spots left',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.linkGreen,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.accentTeal),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrantsRow extends StatelessWidget {
  const _RegistrantsRow({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    final count = event.registrationCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Registrants',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
            Text(
              '$count Joined',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accentTeal,
              ),
            ),
          ],
        ),
        if (event.capacity != null) ...[
          const SizedBox(height: 2),
          Text(
            'Capacity: ${event.capacity} slots',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
        if (count == 0) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 32,
                  color: AppColors.muted,
                ),
                SizedBox(height: 8),
                Text(
                  'No one has registered yet',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.event,
    required this.busy,
    required this.onRegister,
    required this.onUnregister,
  });
  final Event event;
  final bool busy;
  final VoidCallback onRegister;
  final VoidCallback onUnregister;

  @override
  Widget build(BuildContext context) {
    final reg = event.myRegistration;
    final full = event.capacity != null && (event.spotsLeft ?? 1) <= 0;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL ENTRY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.muted,
                  ),
                ),
                Text(
                  event.feeCentavos > 0
                      ? '₱${(event.feeCentavos / 100).toStringAsFixed(0)}'
                      : 'Free',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 48,
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : reg != null
                    ? OutlinedButton(
                        onPressed: onUnregister,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.errorText,
                          side: const BorderSide(color: AppColors.errorText),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(
                          reg.paymentStatus == 'paid'
                              ? 'Registered · Paid — Unregister'
                              : 'Registered — Unregister',
                        ),
                      )
                    : FilledButton(
                        onPressed: full ? null : onRegister,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentTeal,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.disabledBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(full ? 'Full' : 'Register  →'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
