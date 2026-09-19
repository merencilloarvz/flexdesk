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

  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = GymTime.today();
    final events = _events ?? const <Event>[];
    final upcoming = events.where((e) => !e.eventDate.isBefore(today)).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    final past = events.where((e) => e.eventDate.isBefore(today)).toList()
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
    final tabEvents = switch (_tab) {
      _EventTab.upcoming => upcoming,
      _EventTab.past => past,
      _EventTab.all => events,
    };
    final visible = _searchQuery.isEmpty
        ? tabEvents
        : tabEvents.where((e) {
            return e.title.toLowerCase().contains(_searchQuery) ||
                e.description.toLowerCase().contains(_searchQuery) ||
                e.locationText.toLowerCase().contains(_searchQuery);
          }).toList();

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
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: AppColors.accentTeal,
        child: const Icon(Icons.add, color: Colors.white),
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
                  if (_isSearching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: 'Search events...',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.accentTeal,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: AppColors.cardBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.accentTeal,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.fieldBg,
                        borderRadius: BorderRadius.circular(999),
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
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentTeal,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (visible.isEmpty) {
                            return ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: const _TabEmptyState(),
                                ),
                              ],
                            );
                          }
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                            children: [
                              _SectionHeader(tab: _tab, count: visible.length),
                              const SizedBox(height: 10),
                              for (final e in visible)
                                _EventCard(
                                  event: e,
                                  onTap: () => _openDetail(e),
                                ),
                            ],
                          );
                        },
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
          borderRadius: BorderRadius.circular(999),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.tab, required this.count});
  final _EventTab tab;
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = switch (tab) {
      _EventTab.upcoming => 'Upcoming Highlights',
      _EventTab.past => 'Past Events',
      _EventTab.all => 'All Events',
    };

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.accentTeal,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accentTealBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count event${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.accentTeal,
            ),
          ),
        ),
      ],
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
    var dateLabel = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    if (event.startTime != null) dateLabel += ' · ${event.startTime}';
    final today = GymTime.today();
    final isPast = event.eventDate.isBefore(today);
    // Date-only comparison never flips for the rest of the event's own
    // day — a 6pm event would read "REGISTRATION OPEN" at 11pm without
    // this. Only meaningful when start_time exists.
    final startedToday = !isPast &&
        !event.eventDate.isAfter(today) &&
        event.startTime != null &&
        !GymTime.now().isBefore(_startMoment(event));
    final full =
        event.capacity != null && event.registrationCount >= event.capacity!;

    final (statusBg, statusText, statusLabel) = switch (true) {
      _ when event.isCanceled => (
        AppColors.errorBg,
        AppColors.errorText,
        'CANCELLED',
      ),
      _ when isPast => (AppColors.fieldBg, AppColors.subtle, 'COMPLETED'),
      _ when startedToday => (
        AppColors.fieldBg,
        AppColors.subtle,
        'IN PROGRESS',
      ),
      _ when full => (AppColors.errorBg, AppColors.errorText, 'FULL'),
      _ when event.feeCentavos > 0 => (
        AppColors.accentTealBg,
        AppColors.accentTeal,
        'REGISTRATION OPEN',
      ),
      _ => (AppColors.fieldBg, AppColors.subtle, 'UPCOMING'),
    };

    final priceLabel = event.feeCentavos > 0
        ? '₱${(event.feeCentavos / 100).toStringAsFixed(0)}'
        : 'Free';

    return Opacity(
      opacity: event.isCanceled ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: statusText,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        priceLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentTeal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.subtle,
                        ),
                      ),
                    ],
                  ),
                  if (event.locationText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 13,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            event.locationText,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.subtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.fieldBg),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _AvatarStack(count: event.registrationCount),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${event.registrationCount} Registrant${event.registrationCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.subtle,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: onTap,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View Details',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentTeal,
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: AppColors.accentTeal,
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final shown = count.clamp(0, 3);
    if (shown == 0) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 18.0 + (shown - 1) * 14.0,
      height: 24,
      child: Stack(
        children: [
          for (var i = 0; i < shown; i++)
            Positioned(
              left: i * 14.0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accentTealBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBg, width: 1.5),
                ),
                child: const Icon(
                  Icons.person,
                  size: 13,
                  color: AppColors.accentTeal,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_busy_outlined,
              size: 40,
              color: AppColors.muted,
            ),
            const SizedBox(height: 10),
            const Text(
              'No events yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.subtle,
              ),
            ),
          ],
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
