import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/money.dart';
import '../providers/me_providers.dart';

class MemberMembershipScreen extends ConsumerStatefulWidget {
  const MemberMembershipScreen({super.key});

  @override
  ConsumerState<MemberMembershipScreen> createState() =>
      _MemberMembershipScreenState();
}

class _MemberMembershipScreenState
    extends ConsumerState<MemberMembershipScreen> {
  final _items = <Map<String, dynamic>>[];
  final _scrollController = ScrollController();

  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingFirst = true;
  bool _isLoadingMore = false;
  String? _firstLoadError;
  int _currentIndex = -1;

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

  void _recomputeCurrentIndex() {
    // Mirrors the backend's own definition of "current" — the latest
    // non-canceled membership. Since the list is ordered -end_date,
    // the first non-canceled row we see IS that membership; later
    // non-canceled rows are past renewals, not the current one.
    _currentIndex = _items.indexWhere((m) => m['canceled_at'] == null);
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoadingFirst = true;
      _firstLoadError = null;
    });
    try {
      final page = await ref.read(meRepositoryProvider).fetchMembershipPage(1);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(page.items);
          _page = 1;
          _hasMore = page.hasMore;
          _isLoadingFirst = false;
          _recomputeCurrentIndex();
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
          _firstLoadError = "Couldn't load your membership history.";
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    setState(() => _isLoadingMore = true);
    try {
      final page = await ref
          .read(meRepositoryProvider)
          .fetchMembershipPage(_page + 1);
      if (mounted) {
        setState(() {
          _items.addAll(page.items);
          _page += 1;
          _hasMore = page.hasMore;
          _isLoadingMore = false;
          _recomputeCurrentIndex();
        });
      }
    } catch (_) {
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
          'Membership history',
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
                  'No membership history yet.',
                  style: TextStyle(color: AppColors.subtle),
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadFirstPage,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                    final planName = json['plan_name'] as String? ?? 'Plan';
                    final startDate = DateTime.tryParse(
                      json['start_date'] as String? ?? '',
                    );
                    final endDate = DateTime.tryParse(
                      json['end_date'] as String? ?? '',
                    );
                    final priceCents = json['price_paid'] != null
                        ? parseCentavos(json['price_paid'] as String)
                        : null;
                    final isCurrent = index == _currentIndex;
                    final isCanceled = json['canceled_at'] != null;

                    final dateRange = startDate != null && endDate != null
                        ? '${DateFormat('MMM d, yyyy').format(startDate)} – '
                              '${DateFormat('MMM d, yyyy').format(endDate)}'
                        : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent
                            ? Border.all(color: AppColors.activeBg, width: 1.5)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      planName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.activeBg,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: const Text(
                                          'Current',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (isCanceled) ...[
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Cancelled',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.errorText,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (dateRange.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    dateRange,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (priceCents != null)
                            Text(
                              '${currencySymbol('PHP')}'
                              '${centavosToDecimalString(priceCents)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.subtle,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
