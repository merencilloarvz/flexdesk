import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';
import '../data/community_repository.dart';
import 'accent_card.dart';
import 'engagement_row.dart';
import 'type_tag.dart';

/// An event as a post card: type tag and fee pill, title, a two-line
/// description, date and place, and the like/comment footer. Used by the
/// community feed and by "Upcoming Events" on the member home, so an event
/// looks the same wherever it appears.
///
/// The whole card opens the event ([onOpen]); the comment chip goes there
/// too, since an event's comments live on its detail screen.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.onOpen,
    required this.onToggleLike,
    required this.onLikeChanged,
  });

  final Event event;
  final VoidCallback onOpen;
  final Future<LikeState> Function() onToggleLike;
  final ValueChanged<LikeState> onLikeChanged;

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accent: AppColors.expiringBg,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TypeTag.event(),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentTealBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  event.feeCentavos > 0
                      ? '₱${(event.feeCentavos / 100).toStringAsFixed(0)}'
                      : 'Free',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentTeal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.25,
            ),
          ),
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              event.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.subtle,
                height: 1.4,
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
              const SizedBox(width: 5),
              Text(
                DateFormat('MMM d, yyyy').format(event.eventDate),
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              if (event.locationText.isNotEmpty) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.place_outlined,
                  size: 13,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    event.locationText,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          EngagementRow(
            likeCount: event.likeCount,
            likedByMe: event.likedByMe,
            commentCount: event.commentCount,
            onToggleLike: onToggleLike,
            onLikeChanged: onLikeChanged,
            onCommentsTap: onOpen,
          ),
        ],
      ),
    );
  }
}
