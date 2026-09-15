import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/csv_writer.dart';
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

String _csvTypeLabel(String type) {
  switch (type) {
    case 'member':
      return 'Membership';
    case 'retail':
      return 'Retail POS';
    default:
      return 'Walk-in';
  }
}

String _weekStatusLabel(String status) {
  switch (status) {
    case 'in_progress':
      return 'In Progress';
    case 'peak':
      return 'Peak Week';
    case 'opener':
      return 'Month Opener';
    default:
      return 'Change';
  }
}

/// 1D/1W export — one row per transaction, flattened out of the
/// on-screen day groups; a Date column keeps the day info that
/// flattening would otherwise lose. Row order matches what's shown
/// on screen (newest first).
String _buildGroupedCsv(List<_DayGroup> groups) {
  final dateFormat = DateFormat('yyyy-MM-dd');
  final rows = <List<Object?>>[];
  for (final group in groups) {
    final dateStr = dateFormat.format(group.date);
    for (final t in group.transactions) {
      rows.add([dateStr, _csvTypeLabel(t.type), t.title, t.subtitle, t.amount.toStringAsFixed(2)]);
    }
  }
  return buildCsv(
    ['Date', 'Type', 'Description', 'Details', 'Amount (PHP)'],
    rows,
  );
}

/// 1M export — one row per week, oldest (Week 1) first, the
/// conventional top-to-bottom reading order for a spreadsheet even
/// though the on-screen cards run newest-first.
String _buildWeeklyCsv(List<_WeekRollup> weeks) {
  final dateFormat = DateFormat('yyyy-MM-dd');
  final chronological = weeks.reversed.toList();
  final rows = <List<Object?>>[];
  for (var i = 0; i < chronological.length; i++) {
    final w = chronological[i];
    rows.add([
      'Week ${i + 1}',
      dateFormat.format(w.startDate),
      dateFormat.format(w.endDate),
      _weekStatusLabel(w.status),
      w.changePct?.toStringAsFixed(1) ?? '',
      w.orderCount,
      w.total.toStringAsFixed(2),
      (w.categories['membership'] ?? 0).toStringAsFixed(2),
      (w.categories['retail'] ?? 0).toStringAsFixed(2),
      (w.categories['walk_ins'] ?? 0).toStringAsFixed(2),
    ]);
  }
  return buildCsv(
    [
      'Week', 'Start Date', 'End Date', 'Status', 'Change %', 'Order Count',
      'Total (PHP)', 'Membership (PHP)', 'Retail POS (PHP)', 'Walk-ins (PHP)',
    ],
    rows,
  );
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

/// One 7-day (or, for the newest bucket, shorter) rollup, as returned
/// by /analytics/sales-history/ for range=1M.
class _WeekRollup {
  const _WeekRollup({
    required this.startDate,
    required this.endDate,
    required this.total,
    required this.orderCount,
    required this.categories,
    required this.status,
    required this.changePct,
  });

  final DateTime startDate;
  final DateTime endDate;
  final double total;
  final int orderCount;
  final Map<String, double> categories;

  /// 'in_progress' | 'peak' | 'opener' | 'change'.
  final String status;
  final double? changePct;

  factory _WeekRollup.fromJson(Map<String, dynamic> json) {
    return _WeekRollup(
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      total: double.parse(json['total'].toString()),
      orderCount: json['order_count'] as int,
      categories: (json['categories'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, double.parse(v.toString())),
      ),
      status: json['status'] as String,
      changePct: (json['change_pct'] as num?)?.toDouble(),
    );
  }
}

/// Full transaction list behind the Activity Log card's "View All"
/// link — same three sources (walk-in check-ins, memberships, sales)
/// and the same 1D/1W/1M ranges as Sales Overview.
///
/// 1D/1W show transactions grouped by calendar day; 1M shows weekly
/// rollup cards instead (week range, total, category breakdown,
/// status) — a genuinely different layout for that range, not a
/// reshape of the day-grouped list.
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

  // 1M state.
  List<_WeekRollup> _weeks = const [];

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
      if (_range == '1M') {
        setState(() {
          _weeks = (json['weeks'] as List)
              .map((w) => _WeekRollup.fromJson(w as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _period = _Period.fromJson(json['period'] as Map<String, dynamic>);
          _groups = (json['groups'] as List)
              .map((g) => _DayGroup.fromJson(g as Map<String, dynamic>))
              .toList();
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

  void _setRange(String range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _period = null;
      _groups = const [];
      _weeks = const [];
    });
    _load();
  }

  bool _exporting = false;

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = _range == '1M' ? _buildWeeklyCsv(_weeks) : _buildGroupedCsv(_groups);
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/sales-history-${_range.toLowerCase()}-$stamp.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Sales History ($_range)'),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't export — please try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
    return _isGrouped ? _buildGroupedBody() : _buildWeeklyRollupBody();
  }

  Widget _buildGroupedBody() {
    final period = _period;
    if (period == null || (period.orderCount == 0 && _groups.isEmpty)) {
      return Column(
        children: [
          if (period != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SummaryCard(
                period: period,
                range: _range,
                exporting: _exporting,
                onExport: _exportCsv,
              ),
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
        _SummaryCard(
          period: period,
          range: _range,
          exporting: _exporting,
          onExport: _exportCsv,
        ),
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

  Widget _buildWeeklyRollupBody() {
    if (_weeks.isEmpty) {
      return const Center(
        child: Text(
          'No transactions in this range.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      );
    }

    // 1M has no separate period-summary endpoint of its own — it's
    // just the sum of the weeks already on screen.
    final monthPeriod = _Period(
      total: _weeks.fold<double>(0, (sum, w) => sum + w.total),
      orderCount: _weeks.fold<int>(0, (sum, w) => sum + w.orderCount),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _SummaryCard(
            period: monthPeriod,
            range: _range,
            exporting: _exporting,
            onExport: _exportCsv,
          ),
        ),
        Expanded(child: _buildWeeklyRollupList()),
      ],
    );
  }

  Widget _buildWeeklyRollupList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _weeks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        // Returned newest-first; the oldest (last) entry is Week 1.
        final weekNumber = _weeks.length - index;
        return _WeekRollupCard(week: _weeks[index], weekNumber: weekNumber);
      },
    );
  }
}

String _periodNoun(String range) {
  switch (range) {
    case '1D':
      return 'Today';
    case '1M':
      return 'This Month';
    default:
      return 'This Week';
  }
}

/// Total + order count + an Export button that shares the currently
/// viewed range as a CSV via the platform share sheet.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.period,
    required this.range,
    required this.exporting,
    required this.onExport,
  });

  final _Period period;
  final String range;
  final bool exporting;
  final VoidCallback onExport;

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
          TextButton.icon(
            onPressed: exporting ? null : onExport,
            icon: exporting
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentTeal,
                    ),
                  )
                : const Icon(Icons.ios_share, size: 15),
            label: Text(exporting ? 'Exporting…' : 'Export'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentTeal,
              disabledForegroundColor: AppColors.muted,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: AppColors.accentTealBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
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

String _weekDateRangeLabel(DateTime start, DateTime end) {
  if (start.month == end.month) {
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('d').format(end)}';
  }
  return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(end)}';
}

/// One week's rollup — range, status, total, and a
/// Membership/Retail/Walk-ins breakdown. `weekNumber` counts from the
/// oldest bucket (Week 1) even though the list itself is newest-first.
class _WeekRollupCard extends StatelessWidget {
  const _WeekRollupCard({required this.week, required this.weekNumber});

  final _WeekRollup week;
  final int weekNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Week $weekNumber (${_weekDateRangeLabel(week.startDate, week.endDate)})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _WeekStatusBadge(status: week.status, changePct: week.changePct),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${week.orderCount} order${week.orderCount == 1 ? '' : 's'} registered',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            _formatPeso(week.total),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CategoryAmount(
                  label: 'Membership',
                  amount: week.categories['membership'] ?? 0,
                ),
              ),
              Expanded(
                child: _CategoryAmount(
                  label: 'Retail POS',
                  amount: week.categories['retail'] ?? 0,
                ),
              ),
              Expanded(
                child: _CategoryAmount(
                  label: 'Walk-ins',
                  amount: week.categories['walk_ins'] ?? 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryAmount extends StatelessWidget {
  const _CategoryAmount({
    required this.label,
    required this.amount,
  });

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _formatPeso(amount),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// "IN PROGRESS" (live pill) / "Peak week" (highlighted pill) /
/// "Month opener" (plain muted text, week 1 only) / "+12.0% vs last
/// wk" (green/red pill, same up-down convention as the Sales Overview
/// card's own revenue-change badge).
class _WeekStatusBadge extends StatelessWidget {
  const _WeekStatusBadge({required this.status, required this.changePct});

  final String status;
  final double? changePct;

  Widget _pill(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'in_progress':
        return _pill('IN PROGRESS', AppColors.successBg, AppColors.linkGreen);
      case 'peak':
        return _pill(
          'Peak week',
          AppColors.categoryAmber.withValues(alpha: 0.16),
          AppColors.categoryAmber,
        );
      case 'opener':
        return const Text(
          'Month opener',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        );
      case 'change':
      default:
        final pct = changePct;
        if (pct == null) {
          return const Text(
            'vs last week',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          );
        }
        final positive = pct >= 0;
        return _pill(
          '${positive ? '+' : ''}${pct.toStringAsFixed(1)}% vs last wk',
          positive ? AppColors.successBg : AppColors.errorBg,
          positive ? AppColors.linkGreen : AppColors.errorText,
        );
    }
  }
}
