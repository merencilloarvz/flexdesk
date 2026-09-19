import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/community_repository.dart';
import 'like_button.dart';

/// The quiet like + comment-count footer shared by every post card (feed
/// announcements, feed events, and the event card on the member home).
class EngagementRow extends StatelessWidget {
  const EngagementRow({
    super.key,
    required this.likeCount,
    required this.likedByMe,
    required this.commentCount,
    required this.onToggleLike,
    required this.onLikeChanged,
    required this.onCommentsTap,
  });

  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final Future<LikeState> Function() onToggleLike;
  final ValueChanged<LikeState> onLikeChanged;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 4),
        // Nudged left by the buttons' own padding so the heart lines up
        // with the card's text edge.
        Transform.translate(
          offset: const Offset(-6, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LikeButton(
                  likeCount: likeCount,
                  likedByMe: likedByMe,
                  onToggle: onToggleLike,
                  onChanged: onLikeChanged,
                ),
                const SizedBox(width: 6),
                CommentCountChip(count: commentCount, onTap: onCommentsTap),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
