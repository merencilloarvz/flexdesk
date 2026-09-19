import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/gym_time.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import '../../widgets/accent_card.dart';
import '../../widgets/comments_section.dart';
import '../../widgets/like_button.dart';
import '../../widgets/type_tag.dart';

class AnnouncementDetailScreen extends ConsumerStatefulWidget {
  const AnnouncementDetailScreen({super.key, required this.announcementId});
  final String announcementId;

  @override
  ConsumerState<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState
    extends ConsumerState<AnnouncementDetailScreen> {
  Announcement? _announcement;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final announcement = await ref
          .read(communityRepositoryProvider)
          .fetchAnnouncement(widget.announcementId);
      if (!mounted) return;
      setState(() {
        _announcement = announcement;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.kind) {
          ApiExceptionKind.network =>
            'You need an internet connection to view this announcement.',
          ApiExceptionKind.notFound =>
            'This announcement is no longer available.',
          _ => e.message,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = _announcement;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Announcement',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.subtle),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : announcement == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accentTeal,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    AccentCard(
                      accent: AppColors.accentTeal,
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
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Posted ${DateFormat('MMM d, yyyy').format(GymTime.toGymLocal(announcement.createdAt))}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            announcement.body,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.subtle,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: AppColors.border),
                          const SizedBox(height: 4),
                          // Nudged left by the button's own padding so the
                          // heart lines up with the text edge.
                          Transform.translate(
                            offset: const Offset(-6, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: LikeButton(
                                likeCount: announcement.likeCount,
                                likedByMe: announcement.likedByMe,
                                onToggle: () => ref
                                    .read(communityRepositoryProvider)
                                    .toggleLike(
                                      CommunityItemType.announcement,
                                      announcement.id,
                                    ),
                                onChanged: (s) {
                                  if (!mounted) return;
                                  setState(
                                    () => _announcement = announcement
                                        .withEngagement(
                                          likeCount: s.likeCount,
                                          likedByMe: s.likedByMe,
                                        ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    CommentsSection(
                      itemType: CommunityItemType.announcement,
                      itemId: announcement.id,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
