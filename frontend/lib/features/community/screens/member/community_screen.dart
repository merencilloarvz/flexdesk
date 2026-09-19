import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../../shell/app_shell.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import '../../widgets/accent_card.dart';
import '../../widgets/engagement_row.dart';
import '../../widgets/event_card.dart';
import '../../widgets/type_tag.dart';
import 'announcement_detail_screen.dart';
import 'member_event_detail_screen.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

/// One entry in the merged feed — either a real announcement or a real
/// event, never sample/placeholder data.
class _FeedItem {
  _FeedItem.announcement(this.announcement)
    : event = null,
      sortDate = announcement!.createdAt;
  _FeedItem.event(this.event)
    : announcement = null,
      sortDate = event!.eventDate;

  final Announcement? announcement;
  final Event? event;
  final DateTime sortDate;
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openAnnouncement(Announcement a) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(announcementId: a.id),
      ),
    );
    // Likes and comments made on the detail screen show up here on return.
    _loadAnnouncements();
  }

  // ---- likes ----
  // A card reports the server's confirmed numbers back here so the list
  // stays current without a refetch (pull-to-refresh still replaces all).

  void _patchAnnouncementLikes(String id, LikeState like) {
    final list = _announcements;
    if (!mounted || list == null) return;
    setState(() {
      _announcements = [
        for (final a in list)
          a.id == id
              ? a.withEngagement(
                  likeCount: like.likeCount,
                  likedByMe: like.likedByMe,
                )
              : a,
      ];
    });
  }

  void _patchEventLikes(String id, LikeState like) {
    final list = _events;
    if (!mounted || list == null) return;
    setState(() {
      _events = [
        for (final e in list)
          e.id == id
              ? e.withEngagement(
                  likeCount: like.likeCount,
                  likedByMe: like.likedByMe,
                )
              : e,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = _announcements == null && _events == null;
    final bothFailed = _announcementsError != null &&
        _events == null &&
        _announcements == null;

    final items = <_FeedItem>[
      for (final a in _announcements ?? const <Announcement>[])
        _FeedItem.announcement(a),
      for (final e in _events ?? const <Event>[]) _FeedItem.event(e),
    ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    final filtered = _searchQuery.isEmpty
        ? items
        : items.where((item) {
            final a = item.announcement;
            final e = item.event;
            if (a != null) {
              return a.title.toLowerCase().contains(_searchQuery) ||
                  a.body.toLowerCase().contains(_searchQuery);
            }
            return e!.title.toLowerCase().contains(_searchQuery) ||
                e.description.toLowerCase().contains(_searchQuery) ||
                e.locationText.toLowerCase().contains(_searchQuery);
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            if (_isSearching) _buildSearchBar(),
            if (_isSearching && _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 2, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentTeal,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: bothFailed
                  ? _buildError()
                  : loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? _EmptyFeed(searching: _searchQuery.isNotEmpty)
                  : RefreshIndicator(
                      onRefresh: () =>
                          Future.wait([_loadAnnouncements(), _loadEvents()]),
                      color: AppColors.accentTeal,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          AppShell.reservedNavHeight + 24,
                        ),
                        children: [
                          for (final item in filtered) ...[
                            if (item.announcement != null)
                              _AnnouncementCard(
                                key: ValueKey('a-${item.announcement!.id}'),
                                announcement: item.announcement!,
                                onOpen: () =>
                                    _openAnnouncement(item.announcement!),
                                onToggleLike: () => ref
                                    .read(communityRepositoryProvider)
                                    .toggleLike(
                                      CommunityItemType.announcement,
                                      item.announcement!.id,
                                    ),
                                onLikeChanged: (s) => _patchAnnouncementLikes(
                                  item.announcement!.id,
                                  s,
                                ),
                              )
                            else
                              EventCard(
                                key: ValueKey('e-${item.event!.id}'),
                                event: item.event!,
                                onOpen: () => _openEvent(item.event!),
                                onToggleLike: () => ref
                                    .read(communityRepositoryProvider)
                                    .toggleLike(
                                      CommunityItemType.event,
                                      item.event!.id,
                                    ),
                                onLikeChanged: (s) =>
                                    _patchEventLikes(item.event!.id, s),
                              ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _announcementsError ?? _eventsError ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.errorText),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                _loadAnnouncements();
                _loadEvents();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Community',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Stay connected with announcements and events.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.subtle,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildCircularIconButton(
            icon: _isSearching ? Icons.close : Icons.search,
            onTap: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircularIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 20, color: AppColors.ink),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentTeal.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (val) =>
              setState(() => _searchQuery = val.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Search announcements and events...',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
            prefixIcon: const Icon(
              Icons.search,
              size: 20,
              color: AppColors.accentTeal,
            ),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    onPressed: () => setState(() {
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            filled: true,
            fillColor: AppColors.cardBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.accentTeal,
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.searching});

  /// True when the feed is empty because of a search, not because there's
  /// nothing posted.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.accentTealBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                searching ? Icons.search_off_rounded : Icons.forum_outlined,
                size: 32,
                color: AppColors.accentTeal,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'No matches found' : 'No updates yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a different word, or clear your search.'
                  : 'Announcements and events from your gym will show up here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.subtle,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A body preview clipped to [maxLines]; when it really is cut off, a
/// "Read more" hint shows that the full text is on the detail screen.
class _BodyPreview extends StatelessWidget {
  const _BodyPreview({required this.text});

  final String text;

  static const maxLines = 3;

  static const _style = TextStyle(
    fontSize: 13,
    color: AppColors.subtle,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: _style),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        final truncated = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: _style,
            ),
            if (truncated)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Read more',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentTeal,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onOpen,
    required this.onToggleLike,
    required this.onLikeChanged,
  });
  final Announcement announcement;
  final VoidCallback onOpen;
  final Future<LikeState> Function() onToggleLike;
  final ValueChanged<LikeState> onLikeChanged;

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accent: AppColors.accentTeal,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TypeTag.announcement(),
              const Spacer(),
              if (announcement.isPinned) const PinnedLabel(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            announcement.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          _BodyPreview(text: announcement.body),
          const SizedBox(height: 10),
          Text(
            DateFormat(
              'MMM d, yyyy',
            ).format(GymTime.toGymLocal(announcement.createdAt)),
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          // The comment chip goes where the comments are: the detail screen.
          EngagementRow(
            likeCount: announcement.likeCount,
            likedByMe: announcement.likedByMe,
            commentCount: announcement.commentCount,
            onToggleLike: onToggleLike,
            onLikeChanged: onLikeChanged,
            onCommentsTap: onOpen,
          ),
        ],
      ),
    );
  }
}
