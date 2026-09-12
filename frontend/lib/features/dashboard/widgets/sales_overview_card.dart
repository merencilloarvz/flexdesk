import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
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

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// Maps each backend category key to its legend/bar color, icon, and a
// short static subtitle. The subtitle text is descriptive copy only —
// not data from the server — same pattern as the color mapping below.
// NOTE: this switch only branches on 'membership' and 'day_pass' plus a
// catch-all — a real data-mapping gap, flagged before, still open.
Color _categoryColor(String category) {
  switch (category) {
    case 'membership':
      return AppColors.accentTeal;
    case 'day_pass':
      return AppColors.categoryTeal;
    default:
      return AppColors.categoryAmber;
  }
}

IconData _categoryIcon(String category) {
  switch (category) {
    case 'membership':
      return Icons.card_membership_outlined;
    case 'day_pass':
      return Icons.person_outline;
    default:
      return Icons.event_outlined;
  }
}

String _categorySubtitle(String category) {
  switch (category) {
    case 'membership':
      return 'Renewals & sign-ups';
    case 'day_pass':
      return 'Walk-in guest passes';
    default:
      return 'Other collections';
  }
}

class SalesOverviewCard extends ConsumerWidget {
  const SalesOverviewCard({super.key, required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final snapshotAsync = ref.watch(
      analyticsProvider((gymId: gymId, range: range)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Sales Overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              _RangeToggle(range: range),
            ],
          ),
          const SizedBox(height: 20),
          snapshotAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                "Couldn't load sales data.",
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
            data: (snapshot) => _SalesContent(snapshot: snapshot),
          ),
        ],
      ),
    );
  }
}

class _RangeToggle extends ConsumerWidget {
  const _RangeToggle({required this.range});
  final String range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onTap: () => ref.read(analyticsRangeProvider.notifier).state = r,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
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

class _SalesContent extends StatelessWidget {
  const _SalesContent({required this.snapshot});
  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final changePct = snapshot.revenueChangePct;
    final showWeekdayLabels = snapshot.series.length <= 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _formatPeso(snapshot.revenueTotal),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1,
                ),
              ),
            ),
            if (changePct != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: changePct >= 0
                      ? AppColors.successBg
                      : AppColors.errorBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: changePct >= 0
                        ? AppColors.linkGreen
                        : AppColors.errorText,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 22),
        // -------------------------------------------------------------
        // CHART — left exactly as-is. Not touched this pass; waiting on
        // the earlier hourly-bar version (or confirmation this daily
        // line chart is the one to keep) before changing anything here.
        // -------------------------------------------------------------
        SizedBox(
          height: showWeekdayLabels ? 210 : 190,
          child: snapshot.series.length < 2
              ? const Center(
                  child: Text(
                    'Not enough data yet',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                )
              : LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (snapshot.series.length - 1).toDouble(),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      show: showWeekdayLabels,
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: showWeekdayLabels,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final i = value.round();
                            if (i < 0 || i >= snapshot.series.length) {
                              return const SizedBox.shrink();
                            }
                            final weekday = snapshot.series[i].date.weekday;
                            final label = _weekdayLabels[weekday - 1];
                            final isWeekend =
                                weekday == DateTime.saturday ||
                                weekday == DateTime.sunday;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isWeekend
                                      ? AppColors.categoryPurple
                                      : AppColors.muted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => AppColors.ink,
                        getTooltipItems: (spots) => spots.map((s) {
                          return LineTooltipItem(
                            _formatPeso(s.y),
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < snapshot.series.length; i++)
                            FlSpot(i.toDouble(), snapshot.series[i].amount),
                        ],
                        isCurved: true,
                        curveSmoothness: 0.35,
                        color: AppColors.accentTeal,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.accentTeal.withValues(alpha: 0.18),
                              AppColors.accentTeal.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 18),
        // -------------------------------------------------------------
        // REVENUE RATIO — back between the chart and the breakdown,
        // where the reference design has it. No "Category performance"
        // header anymore — removed per feedback.
        // -------------------------------------------------------------
        _RevenueRatio(breakdown: snapshot.breakdown),
        const SizedBox(height: 16),
        _BreakdownList(breakdown: snapshot.breakdown),
      ],
    );
  }
}

/// Label + percentage-accounted-for line, with the proportional bar
/// underneath. "100% accounted" is a real computed sum of the
/// breakdown's own percentages, not a hardcoded string.
class _RevenueRatio extends StatelessWidget {
  const _RevenueRatio({required this.breakdown});
  final List<CategoryBreakdown> breakdown;

  @override
  Widget build(BuildContext context) {
    final total = breakdown.fold<double>(0, (sum, b) => sum + b.pct);
    if (total <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Revenue Ratio',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.subtle,
              ),
            ),
            Text(
              '${total.round()}% accounted',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accentTeal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                for (final b in breakdown)
                  Expanded(
                    flex: (b.pct * 10).round().clamp(1, 100000),
                    child: Container(color: _categoryColor(b.category)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Stacked breakdown list — icon in a tinted square, category label +
/// short static subtitle, amount and percentage on the right. Replaces
/// the earlier 3-across card row.
class _BreakdownList extends StatelessWidget {
  const _BreakdownList({required this.breakdown});
  final List<CategoryBreakdown> breakdown;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < breakdown.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _BreakdownRow(breakdown: breakdown[i]),
        ],
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.breakdown});
  final CategoryBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(breakdown.category);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.categoryChipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _categoryIcon(breakdown.category),
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  breakdown.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  _categorySubtitle(breakdown.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPeso(breakdown.amount),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${breakdown.pct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
