import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';

class EventLeaderboardScreen extends ConsumerStatefulWidget {
  const EventLeaderboardScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });
  final String eventId;
  final String eventTitle;

  @override
  ConsumerState<EventLeaderboardScreen> createState() =>
      _EventLeaderboardScreenState();
}

class _EventLeaderboardScreenState
    extends ConsumerState<EventLeaderboardScreen> {
  List<EventResultRow>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await ref
          .read(communityRepositoryProvider)
          .fetchResults(widget.eventId);
      if (!mounted) return;
      setState(() {
        _results = results;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results ?? const <EventResultRow>[];
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text('${widget.eventTitle} — Results')),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : _results == null
            ? const Center(child: CircularProgressIndicator())
            : results.isEmpty
            ? const Center(
                child: Text(
                  'Results not posted yet.',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final r in results)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '#${r.rank}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentTeal,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (r.note.isNotEmpty)
                                  Text(
                                    r.note,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (r.scoreText.isNotEmpty)
                            Text(
                              r.scoreText,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
