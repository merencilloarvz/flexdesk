import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../data/community_repository.dart';

/// A small heart + count for a feed card.
///
/// Optimistic: the heart flips and the count moves the instant it's tapped,
/// then settles on whatever the server actually returns. If the request
/// fails the heart snaps back and a snackbar says so. Taps while a request
/// is in flight are ignored, so a double-tap can't race two toggles.
///
/// [onToggle] does the network call; [onChanged] tells the parent the
/// server-confirmed state so its own copy of the item stays current (the
/// button itself keeps no state beyond the request).
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.likeCount,
    required this.likedByMe,
    required this.onToggle,
    this.onChanged,
  });

  final int likeCount;
  final bool likedByMe;
  final Future<LikeState> Function() onToggle;
  final ValueChanged<LikeState>? onChanged;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  late int _count = widget.likeCount;
  late bool _liked = widget.likedByMe;
  bool _busy = false;

  @override
  void didUpdateWidget(LikeButton old) {
    super.didUpdateWidget(old);
    // A refresh or a parent-side update wins — unless a tap is mid-flight,
    // in which case the response is about to overwrite this anyway.
    if (!_busy &&
        (old.likeCount != widget.likeCount ||
            old.likedByMe != widget.likedByMe)) {
      _count = widget.likeCount;
      _liked = widget.likedByMe;
    }
  }

  Future<void> _tap() async {
    if (_busy) return;
    final prevCount = _count;
    final prevLiked = _liked;
    setState(() {
      _busy = true;
      _liked = !prevLiked;
      _count = prevLiked ? (prevCount - 1).clamp(0, prevCount) : prevCount + 1;
    });
    try {
      final result = await widget.onToggle();
      widget.onChanged?.call(result);
      if (!mounted) return;
      setState(() {
        _liked = result.likedByMe;
        _count = result.likeCount;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = prevLiked;
        _count = prevCount;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : "Couldn't update your like.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // container + excludeSemantics: its own node, announced as one thing
    // ("Like, 3 likes"), not merged into the neighbouring comment chip.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: _liked
          ? 'Unlike, $_count ${_count == 1 ? 'like' : 'likes'}'
          : 'Like, $_count ${_count == 1 ? 'like' : 'likes'}',
      child: InkWell(
        onTap: _tap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _liked ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: _liked ? AppColors.accentTeal : AppColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                '$_count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _liked ? AppColors.accentTeal : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speech-bubble + count, the quiet companion to [LikeButton] on a card.
/// With no [onTap] it's a plain indicator.
class CommentCountChip extends StatelessWidget {
  const CommentCountChip({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      excludeSemantics: true,
      label: '$count ${count == 1 ? 'comment' : 'comments'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 17,
                color: AppColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
