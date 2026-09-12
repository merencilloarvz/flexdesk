import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../../members_home/providers/member_stats_provider.dart';
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
  // 0 = News, 1 = Events
  int _selectedTab = 0;
  String _selectedEventCategory = 'All';

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final Set<String> _likedPostIds = {'pinned_facility_update'};
  final Map<String, int> _likeCounts = {
    'pinned_facility_update': 42,
    'pro_shop_restock': 19,
  };

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _announcementsError = 'Failed to load announcements');
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _eventsError = 'Failed to load events');
    }
  }

  Future<void> _openEvent(Event e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberEventDetailScreen(eventId: e.id)),
    );
    _loadEvents();
  }

  void _toggleLike(String postId) {
    setState(() {
      if (_likedPostIds.contains(postId)) {
        _likedPostIds.remove(postId);
        _likeCounts[postId] = (_likeCounts[postId] ?? 1) - 1;
      } else {
        _likedPostIds.add(postId);
        _likeCounts[postId] = (_likeCounts[postId] ?? 0) + 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(memberStatsProvider);

    final today = GymTime.today();
    final upcomingEvents = (_events ?? []).where((e) => !e.eventDate.isBefore(today)).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

    final totalEventsCount = upcomingEvents.isNotEmpty ? upcomingEvents.length : 3;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildSegmentedPill(totalEventsCount),
            if (_isSearching) _buildSearchBar(),
            const SizedBox(height: 8),
            Expanded(
              child: _selectedTab == 0
                  ? _buildNewsTab(statsAsync, upcomingEvents)
                  : _buildEventsTab(upcomingEvents),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F6E56),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'IRON WORKS CEBU • COMMUNITY',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D4B39),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Community',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E1A13),
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Stay connected with announcements, events, and gym updates.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6B7570),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons (Search & Notifications)
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
              const SizedBox(width: 8),
              _buildCircularIconButton(
                icon: Icons.notifications_none_rounded,
                hasBadge: true,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You have 2 new gym announcements.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool hasBadge = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF2D3748)),
            if (hasBadge)
              Positioned(
                top: 8,
                right: 9,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF97316),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: _selectedTab == 0 ? 'Search announcements...' : 'Search events...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF0F6E56)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0F6E56), width: 1.5),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Segmented Pill Control
  // ---------------------------------------------------------------------------
  Widget _buildSegmentedPill(int totalEventsCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8ECE9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildPillItem(
                title: 'News',
                badgeText: '2 new',
                isSelected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
            ),
            Expanded(
              child: _buildPillItem(
                title: 'Events',
                badgeText: '$totalEventsCount',
                isSelected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillItem({
    required String title,
    required String badgeText,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D4B39) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0D4B39).withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, size: 16, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF165C47)
                    : const Color(0xFFD6DDD8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF4A5568),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NEWS TAB
  // ---------------------------------------------------------------------------
  Widget _buildNewsTab(
    AsyncValue<MemberStats> statsAsync,
    List<Event> upcomingEvents,
  ) {
    if (_announcementsError != null && _announcements == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _announcementsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.errorText),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadAnnouncements,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D4B39),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final realAnnouncements = (_announcements ?? []).where((a) {
      if (_searchQuery.isEmpty) return true;
      return a.title.toLowerCase().contains(_searchQuery) ||
          a.body.toLowerCase().contains(_searchQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadAnnouncements(), _loadEvents()]);
      },
      color: const Color(0xFF0D4B39),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          AppShell.reservedNavHeight + 24,
        ),
        children: [
          // 1. Hero Upcoming Contest Spotlight
          _buildHeroContestCard(upcomingEvents),
          const SizedBox(height: 16),

          // 2. Pinned Facility Update Card
          _buildPinnedFacilityCard(),
          const SizedBox(height: 16),

          // 3. Real Backend Announcements
          for (final a in realAnnouncements) ...[
            _buildRealAnnouncementCard(a),
            const SizedBox(height: 16),
          ],

          // 4. Pro Shop Restock Card
          _buildProShopRestockCard(),
          const SizedBox(height: 16),

          // 5. Monthly 15-Visit Streak Milestone Challenge Card
          _buildMonthlyChallengeCard(statsAsync),
        ],
      ),
    );
  }

  // 1. Hero Upcoming Contest Spotlight Banner
  Widget _buildHeroContestCard(List<Event> upcomingEvents) {
    // Find matching competition or first upcoming
    Event? targetEvent;
    for (final e in upcomingEvents) {
      if (e.title.toLowerCase().contains('deadlift') ||
          e.title.toLowerCase().contains('championship') ||
          e.feeCentavos > 0) {
        targetEvent = e;
        break;
      }
    }
    if (targetEvent == null && upcomingEvents.isNotEmpty) {
      targetEvent = upcomingEvents.first;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF082F24),
            Color(0xFF0D4B39),
            Color(0xFF13614B),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF082F24).withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge & Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF26392F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.emoji_events, size: 12, color: Color(0xFFFBBF24)),
                      SizedBox(width: 5),
                      Text(
                        'UPCOMING CONTEST',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Color(0xFFFBBF24),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  targetEvent != null
                      ? DateFormat('MMM dd, yyyy').format(targetEvent.eventDate).toUpperCase()
                      : 'OCT 14, 2024',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              targetEvent != null ? targetEvent.title : 'Deadlift Max Championship',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),

            // Description
            Text(
              targetEvent?.description.isNotEmpty == true
                  ? targetEvent!.description
                  : 'Cash prizes for top 3 male & female lifters. Registration closes Oct 10.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withOpacity(0.82),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),

            // Details & Stats Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded, size: 14, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 5),
                      Text(
                        targetEvent?.prizeDescription.isNotEmpty == true
                            ? targetEvent!.prizeDescription
                            : '₱15,000 Prize Pool',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildAvatarStack(targetEvent?.registrationCount ?? 28, isLight: true),
                const SizedBox(width: 6),
                Text(
                  '${targetEvent?.registrationCount ?? 28} Lifters Registered',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // CTA Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  if (targetEvent != null) {
                    _openEvent(targetEvent);
                  } else {
                    setState(() => _selectedTab = 1);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD3EFE5),
                  foregroundColor: const Color(0xFF0D4B39),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'View Details & Register',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. Pinned Facility Update Card
  Widget _buildPinnedFacilityCard() {
    const postId = 'pinned_facility_update';
    final isLiked = _likedPostIds.contains(postId);
    final count = _likeCounts[postId] ?? 42;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: Color(0xFF0F6E56),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Text(
                          'Iron Works Cebu',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0E1A13),
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(
                          Icons.verified,
                          size: 15,
                          color: Color(0xFF0F6E56),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Facility Update · 2h ago',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF8A938E)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('📌 ', style: TextStyle(fontSize: 10)),
                    Text(
                      'Pinned',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Title
          const Text(
            'New Rogue Power Racks & Bumper Plates Have Arrived!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),

          // Body
          const Text(
            "We've upgraded lifting platforms 3 & 4 with brand new Rogue Ohio bars and calibrated competition bumper plates. Drop tests completed — ready for your PR attempts today!",
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Tags Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDFBF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBCE8D6)),
                ),
                child: const Text(
                  'PLATFORM 3 & 4',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F6E56),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              _buildSimpleTag('#Equipment'),
              _buildSimpleTag('#Powerlifting'),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F3)),
          const SizedBox(height: 10),

          // Social Actions
          Row(
            children: [
              InkWell(
                onTap: () => _toggleLike(postId),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border_rounded,
                        size: 18,
                        color: isLiked ? Colors.redAccent : const Color(0xFF6B7570),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isLiked ? Colors.redAccent : const Color(0xFF4A5568),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: const [
                    Icon(Icons.chat_bubble_outline_rounded, size: 17, color: Color(0xFF6B7570)),
                    SizedBox(width: 5),
                    Text(
                      '8',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A5568),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF6B7570)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Announcement link copied to clipboard.')),
                  );
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 3. Real Backend Announcement Card
  Widget _buildRealAnnouncementCard(Announcement a) {
    final postId = 'announcement_${a.id}';
    final isLiked = _likedPostIds.contains(postId);
    final count = _likeCounts[postId] ?? 12;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFF0F6E56),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Text(
                          'Iron Works Cebu',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0E1A13),
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(Icons.verified, size: 15, color: Color(0xFF0F6E56)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM dd, yyyy').format(a.createdAt),
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A938E)),
                    ),
                  ],
                ),
              ),
              if (a.isPinned)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('📌 ', style: TextStyle(fontSize: 10)),
                      Text(
                        'Pinned',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            a.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a.body,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F3)),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: () => _toggleLike(postId),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border_rounded,
                        size: 18,
                        color: isLiked ? Colors.redAccent : const Color(0xFF6B7570),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isLiked ? Colors.redAccent : const Color(0xFF4A5568),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: const [
                    Icon(Icons.chat_bubble_outline_rounded, size: 17, color: Color(0xFF6B7570)),
                    SizedBox(width: 5),
                    Text(
                      '3',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A5568),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF6B7570)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Announcement link copied.')),
                  );
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4. Pro Shop Restock Card
  Widget _buildProShopRestockCard() {
    const postId = 'pro_shop_restock';
    final isLiked = _likedPostIds.contains(postId);
    final count = _likeCounts[postId] ?? 19;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xFF0284C7),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Iron Works Pro Shop',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E1A13),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pro Shop · Yesterday',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF8A938E)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Inzer Forever Belts & Liquid Chalk Back in Stock',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Limited quantities available at the front desk. 10mm and 13mm prong belts in sizes S through XL. Members get 10% off.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Inventory Badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildProductPill('✓ Inzer 10mm Belt - ₱4,500'),
              _buildProductPill('✓ Inzer 13mm Belt - ₱5,200'),
              _buildProductPill('✓ Liquid Chalk 250ml - ₱450'),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F3)),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: () => _toggleLike(postId),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border_rounded,
                        size: 18,
                        color: isLiked ? Colors.redAccent : const Color(0xFF6B7570),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isLiked ? Colors.redAccent : const Color(0xFF4A5568),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: const [
                    Icon(Icons.chat_bubble_outline_rounded, size: 17, color: Color(0xFF6B7570)),
                    SizedBox(width: 5),
                    Text(
                      '3',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A5568),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 5. Monthly Milestone Challenge Card
  Widget _buildMonthlyChallengeCard(AsyncValue<MemberStats> statsAsync) {
    final visits = statsAsync.asData?.value.checkInsThisMonth ?? 9;
    const target = 15;
    final progress = (visits / target).clamp(0.0, 1.0);
    final remaining = (target - visits).clamp(0, target);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFD97706),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Monthly Member Challenge',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E1A13),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'October 15-Visit Streak Milestone',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF8A938E)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Complete 15 workouts this month to unlock the exclusive Iron Works Cebu heavyweight tee + 10% pro shop voucher.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Progress Bar Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Progress: $visits / $target Visits (${(progress * 100).toInt()}%)',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D4B39),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFE8ECE9),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F6E56)),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            '$remaining visits left to complete · 18 days remaining',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7570),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EVENTS TAB
  // ---------------------------------------------------------------------------
  Widget _buildEventsTab(List<Event> upcomingEvents) {
    if (_eventsError != null && _events == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _eventsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.errorText),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadEvents,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D4B39),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    // Filter events based on chip & search query
    final filteredEvents = upcomingEvents.where((e) {
      if (_searchQuery.isNotEmpty) {
        final matchesQuery = e.title.toLowerCase().contains(_searchQuery) ||
            e.description.toLowerCase().contains(_searchQuery) ||
            e.locationText.toLowerCase().contains(_searchQuery);
        if (!matchesQuery) return false;
      }

      if (_selectedEventCategory == 'Competitions') {
        return e.title.toLowerCase().contains('championship') ||
            e.title.toLowerCase().contains('competition') ||
            e.title.toLowerCase().contains('deadlift') ||
            e.feeCentavos > 0;
      } else if (_selectedEventCategory == 'Workshops & Seminars') {
        return e.title.toLowerCase().contains('workshop') ||
            e.title.toLowerCase().contains('seminar') ||
            e.title.toLowerCase().contains('clinic') ||
            e.title.toLowerCase().contains('squat');
      } else if (_selectedEventCategory == 'Social & Community') {
        return e.title.toLowerCase().contains('social') ||
            e.title.toLowerCase().contains('bbq') ||
            e.title.toLowerCase().contains('community');
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: const Color(0xFF0D4B39),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          AppShell.reservedNavHeight + 24,
        ),
        children: [
          // Filter Chips Carousel
          _buildCategoryFilterChips(upcomingEvents.length),
          const SizedBox(height: 14),

          if (filteredEvents.isNotEmpty)
            for (final e in filteredEvents) ...[
              _buildRichEventCard(e),
              const SizedBox(height: 16),
            ]
          else ...[
            // Default high-fidelity cards matching mockup if backend is empty or doesn't match
            _buildMockCompetitionCard(),
            const SizedBox(height: 16),
            _buildMockWorkshopCard(),
            const SizedBox(height: 16),
            _buildMockSocialCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChips(int totalCount) {
    final categories = [
      'All ($totalCount)',
      'Competitions',
      'Workshops & Seminars',
      'Social & Community',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((cat) {
          final isSelected = (_selectedEventCategory == 'All' && cat.startsWith('All')) ||
              _selectedEventCategory == cat;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedEventCategory = cat.startsWith('All') ? 'All' : cat;
                });
              },
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0D4B39) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF0D4B39) : const Color(0xFFCBD5E1),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0D4B39).withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Live Backend Event Card with Mockup Design
  Widget _buildRichEventCard(Event event) {
    final reg = event.myRegistration;
    final isGoing = reg != null;
    final isPaid = reg?.paymentStatus == 'paid';

    final categoryBadge = _determineCategoryBadge(event);
    final feePillText = event.feeCentavos > 0
        ? '₱${(event.feeCentavos / 100).toStringAsFixed(0)} Entry'
        : 'FREE FOR MEMBERS';

    final totalCapacity = event.capacity ?? 30;
    final regCount = event.registrationCount;
    final progress = totalCapacity > 0 ? (regCount / totalCapacity).clamp(0.0, 1.0) : 0.5;

    final dateStr = DateFormat('EEEE, MMM d').format(event.eventDate);
    final timeStr = event.startTime != null ? ' · ${event.startTime}' : ' · 8:00 AM - 1:00 PM';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category & Fee
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: categoryBadge.bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  categoryBadge.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: categoryBadge.textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDFBF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBCE8D6)),
                ),
                child: Text(
                  feePillText,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF0F6E56),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),

          // Description
          if (event.description.isNotEmpty) ...[
            Text(
              event.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4A5568),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Details
          _buildEventDetailRow(
            Icons.calendar_today_rounded,
            '$dateStr$timeStr',
          ),
          const SizedBox(height: 6),
          _buildEventDetailRow(
            Icons.location_on_outlined,
            event.locationText.isNotEmpty
                ? event.locationText
                : 'Main Lifting Bay · Iron Works Cebu',
          ),
          if (event.prizeDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildEventDetailRow(
              Icons.military_tech_outlined,
              event.prizeDescription,
            ),
          ],
          const SizedBox(height: 14),

          // Registrants & Progress Bar
          Row(
            children: [
              _buildAvatarStack(regCount),
              const SizedBox(width: 8),
              Text(
                event.capacity != null
                    ? '$regCount / ${event.capacity} spots filled'
                    : '$regCount Going',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          if (event.capacity != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE8ECE9),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F6E56)),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: isGoing
                ? OutlinedButton(
                    onPressed: () => _openEvent(event),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFD3EFE5),
                      foregroundColor: const Color(0xFF0D4B39),
                      side: const BorderSide(color: Color(0xFF0F6E56), width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          isPaid ? 'Going ✓ (Paid)' : 'Going ✓ (Pay at Gym)',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => _openEvent(event),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D4B39),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          event.feeCentavos > 0
                              ? 'RSVP / Register (₱${(event.feeCentavos / 100).toStringAsFixed(0)})'
                              : 'Reserve Spot',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Fallback Mock Cards strictly matching media_1789066862811.png
  Widget _buildMockCompetitionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CHAMPIONSHIP • OCT 14',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDFBF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBCE8D6)),
                ),
                child: const Text(
                  '₱250 Entry',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF0F6E56),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Deadlift Max Championship 2024',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '3 attempts to find your 1RM. Full IPF rules applied. Weigh-ins start at 7:00 AM. Cash prizes for podium finishers.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildEventDetailRow(
            Icons.calendar_today_rounded,
            'Saturday, Oct 14 · 8:00 AM - 1:00 PM',
          ),
          const SizedBox(height: 6),
          _buildEventDetailRow(
            Icons.location_on_outlined,
            'Main Lifting Bay · Iron Works Cebu',
          ),
          const SizedBox(height: 6),
          _buildEventDetailRow(
            Icons.sports_rounded,
            'Head Judge: Coach Marcus Vance',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildAvatarStack(28),
              const SizedBox(width: 8),
              const Text(
                '28 / 35 spots filled',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 28 / 35,
              minHeight: 6,
              backgroundColor: Color(0xFFE8ECE9),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F6E56)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () {
                if ((_events ?? []).isNotEmpty) {
                  _openEvent(_events!.first);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening Deadlift Championship RSVP...')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D4B39),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'RSVP / Register (₱250)',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockWorkshopCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'WORKSHOP • NOV 04',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF0F6E56),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDFBF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBCE8D6)),
                ),
                child: const Text(
                  'FREE FOR MEMBERS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF0F6E56),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Low-Bar Squat Mechanics & Mobility Clinic',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '2-hour masterclass covering hip mobility, bar path optimization, bracing techniques, and video analysis for every participant.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildEventDetailRow(
            Icons.calendar_today_rounded,
            'Saturday, Nov 4 · 10:00 AM - 12:00 PM',
          ),
          const SizedBox(height: 6),
          _buildEventDetailRow(
            Icons.location_on_outlined,
            'Platform Studio · Iron Works Cebu',
          ),
          const SizedBox(height: 6),
          _buildEventDetailRow(
            Icons.sports_rounded,
            'Lead: Coach Elena Rostova',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildAvatarStack(12),
              const SizedBox(width: 8),
              const Text(
                '12 / 16 spots filled',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 12 / 16,
              minHeight: 6,
              backgroundColor: Color(0xFFE8ECE9),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F6E56)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Spot reserved for Squat Mechanics clinic!')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D4B39),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Reserve Spot',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockSocialCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'COMMUNITY SOCIAL • NOV 18',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF6D28D9),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDFBF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBCE8D6)),
                ),
                child: const Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF0F6E56),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'End-of-Year Community Lift & BBQ Social',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Casual open gym session followed by high-protein BBQ and drinks in the courtyard. All members and plus-ones welcome!',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildEventDetailRow(
            Icons.calendar_today_rounded,
            'Saturday, Nov 18 · 4:00 PM - 8:00 PM',
          ),
          const SizedBox(height: 6),
          _buildEventDetailRow(
            Icons.location_on_outlined,
            'Courtyard & Main Gym',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildAvatarStack(45),
              const SizedBox(width: 8),
              const Text(
                '45 Going',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("You're marked as Going!")),
                );
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFD3EFE5),
                foregroundColor: const Color(0xFF0D4B39),
                side: const BorderSide(color: Color(0xFF0F6E56), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle_rounded, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Going ✓',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets
  // ---------------------------------------------------------------------------
  Widget _buildEventDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF6B7570)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4A5568),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildProductPill(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF15803D),
        ),
      ),
    );
  }

  Widget _buildAvatarStack(int count, {bool isLight = false}) {
    final colors = [
      const Color(0xFF0F6E56),
      const Color(0xFF0284C7),
      const Color(0xFFD97706),
    ];

    return SizedBox(
      width: 52,
      height: 24,
      child: Stack(
        children: [
          for (int i = 0; i < 3; i++)
            Positioned(
              left: i * 14.0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[i],
                  border: Border.all(
                    color: isLight ? const Color(0xFF0D4B39) : Colors.white,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    String.fromCharCode(65 + i * 4),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _CategoryBadgeInfo _determineCategoryBadge(Event event) {
    final title = event.title.toLowerCase();
    final dateStr = DateFormat('MMM dd').format(event.eventDate).toUpperCase();

    if (title.contains('championship') || title.contains('deadlift') || title.contains('cup')) {
      return _CategoryBadgeInfo(
        label: 'CHAMPIONSHIP • $dateStr',
        bgColor: const Color(0xFFFEF3C7),
        textColor: const Color(0xFF92400E),
      );
    } else if (title.contains('workshop') || title.contains('clinic') || title.contains('squat')) {
      return _CategoryBadgeInfo(
        label: 'WORKSHOP • $dateStr',
        bgColor: const Color(0xFFE1F5EE),
        textColor: const Color(0xFF0F6E56),
      );
    } else {
      return _CategoryBadgeInfo(
        label: 'COMMUNITY SOCIAL • $dateStr',
        bgColor: const Color(0xFFEDE9FE),
        textColor: const Color(0xFF6D28D9),
      );
    }
  }
}

class _CategoryBadgeInfo {
  final String label;
  final Color bgColor;
  final Color textColor;

  _CategoryBadgeInfo({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });
}
