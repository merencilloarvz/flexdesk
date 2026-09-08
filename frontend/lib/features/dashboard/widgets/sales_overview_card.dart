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

// Maps each backend category key to its legend/bar color. Falls back to
// accentBlue for any category not listed here, so a new category from
// the backend never crashes — it just renders blue until given its own
// color.
Color _categoryColor(String category) {
  switch (category) {
    case 'membership':
      return AppColors.accentBlue;
    case 'day_pass':
      return AppColors.categoryTeal;
    default:
      return AppColors.categoryPurple;
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
                    color: r == range ? AppColors.accentBlue : AppColors.muted,
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
    // Weekday labels only make sense for a short window — 90 labels on
    // the 3M chart would be unreadable. Matches the reference, which
    // shows day labels specifically on the 7D tab.
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
                        color: AppColors.accentBlue,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.accentBlue.withValues(alpha: 0.18),
                              AppColors.accentBlue.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 14),
        _ProportionBar(breakdown: snapshot.breakdown),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < snapshot.breakdown.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == snapshot.breakdown.length - 1 ? 0 : 7,
                  ),
                  child: _BreakdownCard(breakdown: snapshot.breakdown[i]),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The colored horizontal bar between the chart and the breakdown cards —
/// segment widths are proportional to each category's share of revenue,
/// each segment tinted with that category's legend color.
class _ProportionBar extends StatelessWidget {
  const _ProportionBar({required this.breakdown});
  final List<CategoryBreakdown> breakdown;

  @override
  Widget build(BuildContext context) {
    final total = breakdown.fold<double>(0, (sum, b) => sum + b.pct);
    if (total <= 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 5,
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
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.breakdown});
  final CategoryBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(breakdown.category);

    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.categoryChipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  breakdown.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatPeso(breakdown.amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${breakdown.pct.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
