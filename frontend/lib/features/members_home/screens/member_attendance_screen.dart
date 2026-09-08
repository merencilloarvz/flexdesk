import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../providers/me_providers.dart';

class MemberAttendanceScreen extends ConsumerStatefulWidget {
  const MemberAttendanceScreen({super.key});

  @override
  ConsumerState<MemberAttendanceScreen> createState() =>
      _MemberAttendanceScreenState();
}

class _MemberAttendanceScreenState
    extends ConsumerState<MemberAttendanceScreen> {
  final _items = <Map<String, dynamic>>[];
  final _scrollController = ScrollController();

  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingFirst = true;
  bool _isLoadingMore = false;
  String? _firstLoadError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore) return;
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 300) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoadingFirst = true;
      _firstLoadError = null;
    });
    try {
      final page = await ref.read(meRepositoryProvider).fetchCheckInsPage(1);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(page.items);
          _page = 1;
          _hasMore = page.hasMore;
          _isLoadingFirst = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFirst = false;
          _firstLoadError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingFirst = false;
          _firstLoadError = "Couldn't load your attendance.";
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    setState(() => _isLoadingMore = true);
    try {
      final page = await ref
          .read(meRepositoryProvider)
          .fetchCheckInsPage(_page + 1);
      if (mounted) {
        setState(() {
          _items.addAll(page.items);
          _page += 1;
          _hasMore = page.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      // A failed "load more" just stops — the person can scroll away and
      // back, or pull to refresh, to try again. Not worth a banner for
      // a background pagination fetch.
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Attendance',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: _isLoadingFirst
            ? const Center(child: CircularProgressIndicator())
            : _firstLoadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _firstLoadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.subtle),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _loadFirstPage,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _items.isEmpty
            ? const Center(
                child: Text(
                  'No visits recorded yet.',
                  style: TextStyle(color: AppColors.subtle),
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadFirstPage,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final json = _items[index];
                    final checkedInAtUtc = DateTime.parse(
                      json['checked_in_at'] as String,
                    );
                    final gymLocal = GymTime.toGymLocal(checkedInAtUtc);

                    final showMonthHeader =
                        index == 0 ||
                        _monthOf(_items[index - 1]) != _monthOf(json);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showMonthHeader) ...[
                          if (index != 0) const SizedBox(height: 12),
                          Text(
                            DateFormat('MMMM yyyy').format(gymLocal),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.subtle,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
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
                              const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                                color: AppColors.activeBg,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('EEE, d MMM').format(gymLocal),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const Text(
                                      'Member visit',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                DateFormat('h:mm a').format(gymLocal),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.subtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  String _monthOf(Map<String, dynamic> json) {
    final utc = DateTime.parse(json['checked_in_at'] as String);
    final local = GymTime.toGymLocal(utc);
    return '${local.year}-${local.month}';
  }
}
