import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../data/community_repository.dart';
import '../providers/community_providers.dart';

/// Comments for an announcement or event: a composer, then the thread
/// newest-first, loaded a page at a time (a "Load more" button, since this
/// sits inside its parent's scroll view rather than owning one). No edit,
/// no replies — the backend has neither.
///
/// A delete icon shows only when the server says [Comment.canDelete] (own
/// comment, or the viewer is staff moderating).
///
/// [onCountChanged] reports the server's total whenever it's learned or
/// changes (first load, post, delete) so the parent can keep its own
/// count in step.
class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({
    super.key,
    required this.itemType,
    required this.itemId,
    this.onCountChanged,
  });

  final CommunityItemType itemType;
  final String itemId;
  final ValueChanged<int>? onCountChanged;

  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _items = <Comment>[];
  final _input = TextEditingController();

  int _page = 1;
  bool _hasMore = false;
  int _total = 0;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _loadError;

  bool _posting = false;
  String? _deletingId;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _loadFirstPage();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  Future<void> _loadFirstPage() async {
    setState(() {
      _loadingFirst = true;
      _loadError = null;
    });
    try {
      final page = await _repo.fetchCommentsPage(
        widget.itemType,
        widget.itemId,
        1,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = 1;
        _hasMore = page.hasMore;
        _total = page.totalCount;
        _loadingFirst = false;
      });
      widget.onCountChanged?.call(_total);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFirst = false;
        _loadError = e.kind == ApiExceptionKind.network
            ? 'You need an internet connection to view comments.'
            : e.message;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _actionError = null;
    });
    try {
      final page = await _repo.fetchCommentsPage(
        widget.itemType,
        widget.itemId,
        _page + 1,
      );
      if (!mounted) return;
      setState(() {
        // Posting or deleting shifts page boundaries, so a page can repeat
        // a comment already shown — skip those rather than double-list.
        final seen = _items.map((c) => c.id).toSet();
        _items.addAll(page.items.where((c) => !seen.contains(c.id)));
        _page += 1;
        _hasMore = page.hasMore;
        _total = page.totalCount;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _actionError = e.message;
      });
    }
  }

  Future<void> _post() async {
    final text = _input.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() {
      _posting = true;
      _actionError = null;
    });
    try {
      final comment = await _repo.postComment(
        widget.itemType,
        widget.itemId,
        text,
      );
      if (!mounted) return;
      setState(() {
        _items.insert(0, comment);
        _total += 1;
        _posting = false;
        _input.clear();
      });
      widget.onCountChanged?.call(_total);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _actionError = e.message;
      });
    }
  }

  Future<void> _confirmDelete(Comment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment?'),
        content: Text(
          comment.isMine
              ? 'Your comment will be removed.'
              : "Remove ${comment.authorName}'s comment? This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.errorText),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingId = comment.id;
      _actionError = null;
    });
    try {
      await _repo.deleteComment(widget.itemType, widget.itemId, comment.id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((c) => c.id == comment.id);
        _total = (_total - 1).clamp(0, _total);
        _deletingId = null;
      });
      widget.onCountChanged?.call(_total);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingId = null;
        // A 404 means it's already gone (someone else removed it) — the
        // list is stale, not the action wrong, so just drop it.
        if (e.kind == ApiExceptionKind.notFound) {
          _items.removeWhere((c) => c.id == comment.id);
        } else {
          _actionError = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _input.text.trim().isNotEmpty && !_posting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Comments',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($_total)',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: AppColors.fieldBg,
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
            const SizedBox(width: 8),
            _posting
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: canSend ? _post : null,
                    tooltip: 'Post comment',
                    icon: const Icon(Icons.send_rounded, size: 20),
                    color: AppColors.accentTeal,
                    disabledColor: AppColors.disabledLabel,
                  ),
          ],
        ),
        if (_actionError != null) ...[
          const SizedBox(height: 6),
          Text(
            _actionError!,
            style: const TextStyle(fontSize: 12, color: AppColors.errorText),
          ),
        ],
        const SizedBox(height: 8),
        if (_loadingFirst)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_loadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.subtle),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loadFirstPage,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No comments yet. Start the conversation.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          )
        else ...[
          for (final c in _items)
            _CommentTile(
              comment: c,
              deleting: _deletingId == c.id,
              onDelete: () => _confirmDelete(c),
            ),
          if (_hasMore)
            Center(
              child: _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _loadNextPage,
                      child: const Text(
                        'Load more comments',
                        style: TextStyle(color: AppColors.accentTeal),
                      ),
                    ),
            ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.deleting,
    required this.onDelete,
  });

  final Comment comment;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (comment.authorRole) {
      'owner' => 'Owner',
      'member' => null,
      _ => 'Staff',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accentTealBg,
            child: Text(
              _initialsFor(comment.authorName),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accentTeal,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      comment.authorName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (roleLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentTealBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          roleLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: AppColors.accentTeal,
                          ),
                        ),
                      ),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.subtle,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (deleting)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (comment.canDelete)
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete comment',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppColors.muted,
            ),
        ],
      ),
    );
  }
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

/// Relative while it's recent, a date once it isn't. [createdAt] is a real
/// UTC instant, so the difference against now is right in any timezone;
/// the fallback date is shown in the gym's local time.
String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d, yyyy').format(GymTime.toGymLocal(createdAt));
}
