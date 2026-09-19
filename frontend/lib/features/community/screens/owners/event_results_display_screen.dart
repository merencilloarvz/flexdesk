import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import 'event_results_screen.dart';

class EventResultsDisplayScreen extends ConsumerStatefulWidget {
  const EventResultsDisplayScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventResultsDisplayScreen> createState() =>
      _EventResultsDisplayScreenState();
}

class _EventResultsDisplayScreenState
    extends ConsumerState<EventResultsDisplayScreen> {
  Event? _event;
  List<EventResultRow>? _results;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(communityRepositoryProvider);
    try {
      final event = await repo.fetchEvent(widget.eventId);
      final results = await repo.fetchResults(widget.eventId);
      results.sort((a, b) => a.rank.compareTo(b.rank));
      if (!mounted) return;
      setState(() {
        _event = event;
        _results = results;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).verifyResults(widget.eventId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _unverify() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unverify results?'),
        content: const Text(
          'This clears the verified status so you can correct a score. '
          'Members will see these results as unverified until you verify '
          'again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep verified'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unverify'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(communityRepositoryProvider)
          .unverifyResults(widget.eventId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _editResults() async {
    final event = _event;
    if (event == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventResultsScreen(eventId: event.id)),
    );
    await _load();
  }

  void _shareResults() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Results link copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final results = _results ?? const <EventResultRow>[];
    final authState = ref.watch(authControllerProvider);
    final gymName = authState is AuthAuthenticated
        ? authState.user.gym?.name
        : null;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              event?.title ?? 'Event',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            const Text(
              'Leaderboard & Results',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w400,
                fontSize: 12,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: event == null ? null : _editResults,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: event == null ? null : _shareResults,
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : event == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accentTeal,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    _VerificationBanner(
                      event: event,
                      hasResults: results.isNotEmpty,
                      busy: _busy,
                      onVerify: _verify,
                      onUnverify: _unverify,
                    ),
                    const SizedBox(height: 16),
                    _EventInfoCard(event: event, gymName: gymName),
                    if (results.length >= 3) ...[
                      const SizedBox(height: 24),
                      _Podium(results: results.take(3).toList()),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text(
                          'Roster & Scores',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${results.length})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No results posted yet.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    else
                      for (final r in results) _RosterTile(result: r),
                  ],
                ),
              ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({
    required this.event,
    required this.hasResults,
    required this.busy,
    required this.onVerify,
    required this.onUnverify,
  });
  final Event event;
  final bool hasResults;
  final bool busy;
  final VoidCallback onVerify;
  final VoidCallback onUnverify;

  @override
  Widget build(BuildContext context) {
    if (event.resultsVerified) {
      final verifiedAt = event.resultsVerifiedAt;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified,
                  size: 18,
                  color: AppColors.linkGreen,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Official Results Verified',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.linkGreen,
                    ),
                  ),
                ),
              ],
            ),
            if (verifiedAt != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  'Verified ${DateFormat('MMM d, yyyy · h:mm a').format(verifiedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.linkGreen,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onUnverify,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Unverify', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.subtle,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Results Not Yet Verified',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.subtle,
                  ),
                ),
              ),
            ],
          ),
          if (hasResults) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onVerify,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Verify Results'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 26),
              child: Text(
                'Post results before they can be verified.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventInfoCard extends StatelessWidget {
  const _EventInfoCard({required this.event, required this.gymName});
  final Event event;
  final String? gymName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gymName != null) ...[
            Text(
              gymName!.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (event.prizeDescription.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  size: 16,
                  color: AppColors.accentTeal,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event.prizeDescription,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.subtle,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.fieldBg),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.groups_outlined, size: 15, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(
                '${event.registrationCount} entries',
                style: const TextStyle(fontSize: 12, color: AppColors.subtle),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM d, yyyy').format(event.eventDate),
                style: const TextStyle(fontSize: 12, color: AppColors.subtle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _rankLabel(int rank) => switch (rank) {
  1 => '1st',
  2 => '2nd',
  3 => '3rd',
  _ => '${rank}th',
};

(Color, Color) _rankColors(int rank) => switch (rank) {
  1 => (const Color(0xFFFBBF24), const Color(0xFF92400E)), // gold
  2 => (const Color(0xFFD1D5DB), const Color(0xFF374151)), // silver
  3 => (const Color(0xFFDDB892), const Color(0xFF7C4A21)), // bronze
  _ => (AppColors.fieldBg, AppColors.subtle),
};

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

class _Podium extends StatelessWidget {
  const _Podium({required this.results});
  final List<EventResultRow> results;

  @override
  Widget build(BuildContext context) {
    final first = results[0];
    final second = results[1];
    final third = results[2];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumSpot(result: second, elevated: false)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSpot(result: first, elevated: true)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSpot(result: third, elevated: false)),
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({required this.result, required this.elevated});
  final EventResultRow result;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _rankColors(result.rank);
    final size = elevated ? 68.0 : 56.0;
    return Column(
      children: [
        if (elevated)
          const Icon(
            Icons.emoji_events,
            size: 20,
            color: Color(0xFFFBBF24),
          ),
        SizedBox(height: elevated ? 4 : 24),
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBg, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            _initialsFor(result.displayName),
            style: TextStyle(
              fontSize: elevated ? 20 : 16,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _rankLabel(result.rank),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.accentTeal,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          result.displayName,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (result.scoreText.isNotEmpty)
          Text(
            result.scoreText,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
      ],
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.result});
  final EventResultRow result;

  @override
  Widget build(BuildContext context) {
    final medal = result.rank <= 3;
    final (bg, fg) = _rankColors(result.rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal ? bg : AppColors.fieldBg,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${result.rank}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: medal ? fg : AppColors.subtle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accentTealBg,
            child: Text(
              _initialsFor(result.displayName),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accentTeal,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (result.note.isNotEmpty)
                  Text(
                    result.note,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (result.scoreText.isNotEmpty)
            Text(
              result.scoreText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
        ],
      ),
    );
  }
}
