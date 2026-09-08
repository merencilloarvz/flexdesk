import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../../shell/app_shell.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import 'member_event_detail_screen.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  bool _showEvents = false;

  List<Announcement>? _announcements;
  String? _announcementsError;
  List<Event>? _events;
  String? _eventsError;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    _loadEvents();
  }

  Future<void> _loadAnnouncements() async {
    try {
      final items = await ref
          .read(communityRepositoryProvider)
          .fetchAnnouncements();
      if (!mounted) return;
      setState(() {
        _announcements = items;
        _announcementsError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _announcementsError = e.message);
    }
  }

  Future<void> _loadEvents() async {
    try {
      final items = await ref.read(communityRepositoryProvider).fetchEvents();
      if (!mounted) return;
      setState(() {
        _events = items;
        _eventsError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _eventsError = e.message);
    }
  }

  Future<void> _openEvent(Event e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberEventDetailScreen(eventId: e.id)),
    );
    _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('Community')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('News')),
                  ButtonSegment(value: true, label: Text('Events')),
                ],
                selected: {_showEvents},
                onSelectionChanged: (s) =>
                    setState(() => _showEvents = s.first),
              ),
            ),
            Expanded(child: _showEvents ? _buildEvents() : _buildNews()),
          ],
        ),
      ),
    );
  }

  Widget _buildNews() {
    if (_announcementsError != null)
      return Center(child: Text(_announcementsError!));
    if (_announcements == null)
      return const Center(child: CircularProgressIndicator());
    if (_announcements!.isEmpty) {
      return const Center(
        child: Text(
          'No announcements yet.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAnnouncements,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          AppShell.reservedNavHeight + 24,
        ),
        children: [
          for (final a in _announcements!) _AnnouncementCard(announcement: a),
        ],
      ),
    );
  }

  Widget _buildEvents() {
    if (_eventsError != null) return Center(child: Text(_eventsError!));
    if (_events == null)
      return const Center(child: CircularProgressIndicator());
    final today = GymTime.today();
    final upcoming =
        _events!.where((e) => !e.eventDate.isBefore(today)).toList()
          ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    if (upcoming.isEmpty) {
      return const Center(
        child: Text(
          'No upcoming events.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          AppShell.reservedNavHeight + 24,
        ),
        children: [
          for (final e in upcoming)
            _EventCard(event: e, onTap: () => _openEvent(e)),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({required this.announcement});
  final Announcement announcement;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _expanded = false;
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
    final a = widget.announcement;
    final d = a.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (a.isPinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.push_pin,
                      size: 14,
                      color: AppColors.accentTeal,
                    ),
                  ),
                Expanded(
                  child: Text(
                    a.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_months[d.month - 1]} ${d.day}, ${d.year}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            Text(
              a.body,
              maxLines: _expanded ? null : 2,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.subtle, fontSize: 13),
            ),
          ],
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
    final reg = event.myRegistration;
    final statusText = reg == null
        ? 'Register'
        : reg.paymentStatus == 'paid'
        ? 'Registered · Paid'
        : 'Registered · Pay ₱${(reg.amountDueCentavos / 100).toStringAsFixed(0)} at the gym';

    return Opacity(
      opacity: event.isCanceled ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          onTap: onTap,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (event.isCanceled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Cancelled',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.errorText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            '${_months[d.month - 1]} ${d.day}, ${d.year} · ₱${(event.feeCentavos / 100).toStringAsFixed(0)}\n'
            '${event.isCanceled ? "Cancelled" : statusText}'
            '${event.capacity != null && event.spotsLeft != null && !event.isCanceled ? " · ${event.spotsLeft} left" : ""}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          isThreeLine: true,
        ),
      ),
    );
  }
}
