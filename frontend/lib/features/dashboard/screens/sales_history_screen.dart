import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';
import '../providers/analytics_providers.dart';

String _formatPeso(double amount) {
  final formatter = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );
  return formatter.format(amount);
}

Color _activityColor(String type) {
  switch (type) {
    case 'member':
      return AppColors.accentTeal;
    case 'retail':
      return AppColors.categoryAmber;
    default:
      return AppColors.categoryTeal;
  }
}

IconData _activityIcon(String type) {
  switch (type) {
    case 'member':
      return Icons.card_membership_outlined;
    case 'retail':
      return Icons.shopping_bag_outlined;
    default:
      return Icons.directions_walk;
  }
}

/// One calendar day's worth of transactions, as returned by
/// /analytics/sales-history/ for range=1D/1W.
class _DayGroup {
  const _DayGroup({
    required this.date,
    required this.total,
    required this.orderCount,
    required this.transactions,
  });

  final DateTime date;
  final double total;
  final int orderCount;
  final List<RecentActivity> transactions;

  factory _DayGroup.fromJson(Map<String, dynamic> json) {
    return _DayGroup(
      date: DateTime.parse(json['date'] as String),
      total: double.parse(json['total'].toString()),
      orderCount: json['order_count'] as int,
      transactions: (json['transactions'] as List)
          .map((t) => RecentActivity.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _Period {
  const _Period({required this.total, required this.orderCount});

  final double total;
  final int orderCount;

  factory _Period.fromJson(Map<String, dynamic> json) {
    return _Period(
      total: double.parse(json['total'].toString()),
      orderCount: json['order_count'] as int,
    );
  }
}

/// Full transaction list behind the Activity Log card's "View All"
/// link — same three sources (walk-in check-ins, memberships, sales)
/// and the same 1D/1W/1M ranges as Sales Overview.
///
/// 1D/1W show transactions grouped by calendar day (Phase A). 1M
/// still shows the older flat, paginated list for now — Phase B
/// replaces it with weekly rollup cards, matching the reference
/// design's very different layout for that range.
class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key, required this.gymId});

  final String gymId;

  @override
  ConsumerState<SalesHistoryScreen> createState() =>
      _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  String _range = '1D';
  bool _loading = true;
  bool _error = false;

  // 1D/1W state.
  _Period? _period;
  List<_DayGroup> _groups = const [];

  // 1M state — unchanged flat/paginated shape from before Phase A.
  List<RecentActivity> _items = const [];
  String? _nextUrl;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isGrouped => _range != '1M';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final api = ref.read(analyticsApiProvider);
      final json = await api.fetchSalesHistory(range: _range);
      if (!mounted) return;
      if (_isGrouped) {
        setState(() {
          _period = _Period.fromJson(json['period'] as Map<String, dynamic>);
          _groups = (json['groups'] as List)
              .map((g) => _DayGroup.fromJson(g as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      } else {
        final results = json['results'] as List;
        setState(() {
          _items = results
              .map((r) => RecentActivity.fromJson(r as Map<String, dynamic>))
              .toList();
          _nextUrl = json['next'] as String?;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_nextUrl == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final api = ref.read(analyticsApiProvider);
      final json = await api.fetchSalesHistory(
        range: _range,
        pageUrl: _nextUrl,
      );
      final results = json['results'] as List;
      if (!mounted) return;
      setState(() {
        _items = [
          ..._items,
          ...results.map(
            (r) => RecentActivity.fromJson(r as Map<String, dynamic>),
          ),
        ];
        _nextUrl = json['next'] as String?;
        _loadingMore = false;
      });
    } catch (_) {
      _loadingMore = false;
    }
  }

  void _setRange(String range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _period = null;
      _groups = const [];
      _items = const [];
      _nextUrl = null;
    });
    _load();
  }

  void _showSearchStub() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Search is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink),
        title: const Text(
          'Sales History',
          style: TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.ink),
            onPressed: _showSearchStub,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _RangeToggle(range: _range, onChanged: _setRange),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error) {
      return const Center(
        child: Text(
          "Couldn't load sales history.",
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      );
    }
    return _isGrouped ? _buildGroupedBody() : _buildFlatBody();
  }

  Widget _buildGroupedBody() {
    final period = _period;
    if (period == null || (period.orderCount == 0 && _groups.isEmpty)) {
      return Column(
        children: [
          if (period != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SummaryCard(period: period, range: _range),
            ),
          const Expanded(
            child: Center(
              child: Text(
                'No transactions in this range.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          ),
        ],
      );
    }

    final today = DateTime.now();
    final showDaySubheaders = _range == '1W';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _SummaryCard(period: period, range: _range),
        const SizedBox(height: 16),
        _PeriodHeader(range: _range, period: period, today: today),
        const SizedBox(height: 10),
        for (final group in _groups) ...[
          if (showDaySubheaders) ...[
            _DaySubheader(group: group, today: today),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < group.transactions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _SalesHistoryRow(item: group.transactions[i]),
          ],
          const SizedBox(height: 16),
        ],
        Center(
          child: Text(
            _range == '1D' ? 'End of daily records' : 'End of weekly records',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildFlatBody() {
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No transactions in this range.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      );
    }

    final hasMore = _nextUrl != null;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _items.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          // A lazily-built sentinel row: becoming visible is the
          // trigger to fetch the next page, giving infinite scroll
          // without a separate ScrollController.
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return _SalesHistoryRow(item: _items[index]);
      },
    );
  }
}

String _periodNoun(String range) => range == '1D' ? 'Today' : 'This Week';

/// Total + order count + a stubbed Export button (disabled — CSV/PDF
/// export is a separate, not-yet-decided task).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.period, required this.range});

  final _Period period;
  final String range;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL ${_periodNoun(range).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatPeso(period.total),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${period.orderCount} order${period.orderCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          // Export (CSV/PDF) is a separate task — shown but disabled
          // rather than wired to a fake action.
          Tooltip(
            message: 'Export coming soon',
            child: TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.ios_share, size: 15),
              label: const Text('Export'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.muted,
                disabledForegroundColor: AppColors.muted,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                backgroundColor: AppColors.fieldBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Today, October 24" / "This Week (Oct 18 – 24)" with, respectively,
/// a live "Real-time sync" indicator or the period's total record
/// count on the right.
class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({
    required this.range,
    required this.period,
    required this.today,
  });

  final String range;
  final _Period period;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final label = range == '1D'
        ? 'Today, ${DateFormat('MMMM d').format(today)}'
        : 'This Week (${_weekRangeLabel(today)})';

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        if (range == '1D')
          const _LiveSyncIndicator()
        else
          Text(
            '${period.orderCount} records',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
      ],
    );
  }
}

String _weekRangeLabel(DateTime today) {
  final start = today.subtract(const Duration(days: 6));
  if (start.month == today.month) {
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('d').format(today)}';
  }
  return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(today)}';
}

class _LiveSyncIndicator extends StatelessWidget {
  const _LiveSyncIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.linkGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        const Text(
          'Real-time sync',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.linkGreen,
          ),
        ),
      ],
    );
  }
}

/// A day's sub-header within the 1W list — "Yesterday, Oct 23" with
/// that day's own total + order count on the right.
class _DaySubheader extends StatelessWidget {
  const _DaySubheader({required this.group, required this.today});

  final _DayGroup group;
  final DateTime today;

  String get _label {
    final d = DateTime(group.date.year, group.date.month, group.date.day);
    final t = DateTime(today.year, today.month, today.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) return 'Today, ${DateFormat('MMM d').format(d)}';
    if (diff == 1) return 'Yesterday, ${DateFormat('MMM d').format(d)}';
    return DateFormat('EEE, MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.subtle,
            ),
          ),
        ),
        Text(
          '${_formatPeso(group.total)} · ${group.orderCount} order${group.orderCount == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.range, required this.onChanged});

  final String range;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.fieldBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in analyticsRanges)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: r == range ? AppColors.cardBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: r == range
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  r,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: r == range ? AppColors.accentTeal : AppColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SalesHistoryRow extends StatelessWidget {
  const _SalesHistoryRow({required this.item});
  final RecentActivity item;

  @override
  Widget build(BuildContext context) {
    final color = _activityColor(item.type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_activityIcon(item.type), size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatPeso(item.amount),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
