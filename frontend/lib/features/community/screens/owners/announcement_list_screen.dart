import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import 'announcement_edit_screen.dart';

const List<({String label, IconData icon, Color color})> _quickTopics = [
  (
    label: 'Holiday Hours',
    icon: Icons.celebration_outlined,
    color: AppColors.categoryPurple,
  ),
  (
    label: 'Equipment Maintenance',
    icon: Icons.build_outlined,
    color: AppColors.expiringBg,
  ),
];

class AnnouncementsListScreen extends ConsumerStatefulWidget {
  const AnnouncementsListScreen({super.key});

  @override
  ConsumerState<AnnouncementsListScreen> createState() =>
      _AnnouncementsListScreenState();
}

class _AnnouncementsListScreenState
    extends ConsumerState<AnnouncementsListScreen> {
  List<Announcement>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref
          .read(communityRepositoryProvider)
          .fetchAnnouncements();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _openEdit([Announcement? a, String? prefillTitle]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AnnouncementEditScreen(announcement: a, prefillTitle: prefillTitle),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? const <Announcement>[];
    final pinned = items.where((a) => a.isPinned).toList();
    final others = items.where((a) => !a.isPinned).toList();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Announcements',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEdit(),
        backgroundColor: AppColors.accentTeal,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_items != null && _items!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                      '${_items!.length} announcement${_items!.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.accentTeal,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : _items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? _EmptyState(
                      onCreate: () => _openEdit(),
                      onQuickTopic: (label) => _openEdit(null, label),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentTeal,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                        children: [
                          for (final a in pinned)
                            _AnnouncementCard(
                              announcement: a,
                              onTap: () => _openEdit(a),
                            ),
                          if (pinned.isNotEmpty && others.isNotEmpty)
                            const SizedBox(height: 4),
                          for (final a in others)
                            _AnnouncementCard(
                              announcement: a,
                              onTap: () => _openEdit(a),
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

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, required this.onTap});
  final Announcement announcement;
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
    final firstLine = announcement.body.split('\n').first;
    final d = announcement.createdAt.toLocal();
    final dateLabel = '${_months[d.month - 1]} ${d.day}, ${d.year}';

    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: announcement.isPinned
                ? Border.all(color: AppColors.accentTeal, width: 1.2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: announcement.isPinned
                          ? AppColors.accentTeal
                          : AppColors.fieldBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      announcement.isPinned
                          ? Icons.push_pin
                          : Icons.campaign_outlined,
                      size: 14,
                      color: announcement.isPinned
                          ? Colors.white
                          : AppColors.subtle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (announcement.isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentTealBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.push_pin,
                            size: 11,
                            color: AppColors.accentTeal,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'PINNED UPDATE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentTeal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      dateLabel,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                announcement.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                firstLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.subtle,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.arrow_forward,
                    size: 13,
                    color: AppColors.accentTeal,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onQuickTopic});
  final VoidCallback onCreate;
  final ValueChanged<String> onQuickTopic;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.accentTeal,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.campaign, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 18),
          const Text(
            'Keep your members in the loop',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Announcements are short updates members see the moment they open '
            'the app — schedule changes, holiday hours, or gym upgrades.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create First Announcement'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'QUICK DRAFT TOPICS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final topic in _quickTopics) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => onQuickTopic(topic.label),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: topic.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              topic.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (topic != _quickTopics.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
