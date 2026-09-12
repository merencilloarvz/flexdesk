import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import 'event_detail_screen.dart';
import 'event_edit_screen.dart';

enum _EventTab { upcoming, past, all }

class EventsListScreen extends ConsumerStatefulWidget {
  const EventsListScreen({super.key});

  @override
  ConsumerState<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends ConsumerState<EventsListScreen> {
  List<Event>? _events;
  String? _error;
  _EventTab _tab = _EventTab.upcoming;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await ref.read(communityRepositoryProvider).fetchEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EventEditScreen()));
    if (changed == true) _load();
  }

  Future<void> _openDetail(Event e) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: e.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = GymTime.today();
    final events = _events ?? const <Event>[];
    final upcoming = events.where((e) => !e.eventDate.isBefore(today)).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    final past = events.where((e) => e.eventDate.isBefore(today)).toList()
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
    final visible = switch (_tab) {
      _EventTab.upcoming => upcoming,
      _EventTab.past => past,
      _EventTab.all => events,
    };

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Events',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: AppColors.accentTeal,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : _events == null
            ? const Center(child: CircularProgressIndicator())
            : events.isEmpty
            ? _EmptyState(onCreate: _openCreate)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.fieldBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TabButton(
                              label: 'Upcoming (${upcoming.length})',
                              selected: _tab == _EventTab.upcoming,
                              onTap: () =>
                                  setState(() => _tab = _EventTab.upcoming),
                            ),
                          ),
                          Expanded(
                            child: _TabButton(
                              label: 'Past (${past.length})',
                              selected: _tab == _EventTab.past,
                              onTap: () =>
                                  setState(() => _tab = _EventTab.past),
                            ),
                          ),
                          Expanded(
                            child: _TabButton(
                              label: 'All (${events.length})',
                              selected: _tab == _EventTab.all,
                              onTap: () => setState(() => _tab = _EventTab.all),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.accentTeal,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          switch (_tab) {
                            _EventTab.upcoming => 'UPCOMING HIGHLIGHTS',
                            _EventTab.past => 'PAST EVENTS',
                            _EventTab.all => 'ALL EVENTS',
                          },
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: AppColors.subtle,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${visible.length} event${visible.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.accentTeal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(switch (_tab) {
                              _EventTab.upcoming => 'No upcoming events',
                              _EventTab.past => 'No past events',
                              _EventTab.all => 'No events',
                            }, style: const TextStyle(color: AppColors.subtle)),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppColors.accentTeal,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                              children: [
                                for (final e in visible)
                                  _EventCard(
                                    event: e,
                                    onTap: () => _openDetail(e),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentTeal : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});
  final Event event;
  final VoidCallback onTap;

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
    final d = event.eventDate;
    final dateLabel = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    final isPast = event.eventDate.isBefore(GymTime.today());
    final full =
        event.capacity != null && event.registrationCount >= event.capacity!;
    final fillPct = event.capacity != null && event.capacity! > 0
        ? (event.registrationCount / event.capacity! * 100).clamp(0, 100)
        : null;

    final (statusBg, statusText, statusLabel) = switch (true) {
      _ when event.isCanceled => (
        AppColors.errorBg,
        AppColors.errorText,
        'Cancelled',
      ),
      _ when isPast => (AppColors.fieldBg, AppColors.subtle, 'Completed'),
      _ when full => (AppColors.errorBg, AppColors.errorText, 'Full'),
      _ => (AppColors.successBg, AppColors.linkGreen, 'Open for Registration'),
    };

    // Stripe color tied to the SAME real status as the badge above —
    // not a decorative hash like the Schedule cards use, since Events
    // actually has a meaningful status to reflect.
    final stripe = switch (true) {
      _ when event.isCanceled => AppColors.errorText,
      _ when isPast => AppColors.subtle,
      _ when full => AppColors.errorText,
      _ => AppColors.accentTeal,
    };

    return Opacity(
      opacity: event.isCanceled ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: stripe),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusText,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                dateLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          if (event.locationText.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.place_outlined,
                                  size: 13,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    event.locationText,
                                    overflow: TextOverflow.ellipsis,
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          event.capacity != null
                                              ? '${event.registrationCount}/${event.capacity} Registered'
                                              : '${event.registrationCount} Registered',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        if (fillPct != null) ...[
                                          const Spacer(),
                                          Text(
                                            '${fillPct.round()}%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: stripe,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (fillPct != null) ...[
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: LinearProgressIndicator(
                                          value: fillPct / 100,
                                          minHeight: 5,
                                          backgroundColor: AppColors.fieldBg,
                                          valueColor: AlwaysStoppedAnimation(
                                            stripe,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: onTap,
                                icon: Icon(
                                  isPast
                                      ? Icons.visibility_outlined
                                      : Icons.settings_outlined,
                                  size: 15,
                                ),
                                label: Text(
                                  isPast ? 'View Details' : 'Manage',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.ink,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentTeal,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.emoji_events,
                size: 28,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Events are competitions or gatherings members can register and '
              'pay for at the gym — a fun run, a lifting meet, a holiday party.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('Create your first event'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
