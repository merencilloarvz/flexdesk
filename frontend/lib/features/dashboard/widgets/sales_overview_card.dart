import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

<<<<<<< Updated upstream
const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// One rendered point on the chart's x-axis — either a raw daily
/// [RevenuePoint] (1W and shorter) or a week-bucket sum (1M), so the
/// chart and the peak bubble can share one shape regardless of range.
class _ChartPoint {
  const _ChartPoint({
    required this.amount,
    required this.axisLabel,
    required this.peakLabel,
  });

  final double amount;
  final String axisLabel;
  final String peakLabel;
}

/// Builds the points the chart actually plots. 1M has ~30 daily points
/// from the API — too dense for weekday labels — so it's bucketed into
/// 7-day "Week N" chunks here, purely for display; the underlying daily
/// totals from the API are untouched.
List<_ChartPoint> _buildChartPoints(AnalyticsSnapshot snapshot) {
  final series = snapshot.series;
  if (snapshot.range == '1M' && series.length > 7) {
    final points = <_ChartPoint>[];
    for (var start = 0; start < series.length; start += 7) {
      final end = (start + 7 < series.length) ? start + 7 : series.length;
      final sum = series
          .sublist(start, end)
          .fold<double>(0, (s, p) => s + p.amount);
      final weekNum = points.length + 1;
      points.add(
        _ChartPoint(
          amount: sum,
          axisLabel: 'Week $weekNum',
          peakLabel: 'Week $weekNum',
        ),
      );
    }
    return points;
  }

  return series.map((p) {
    final label = _weekdayLabels[p.date.weekday - 1];
    return _ChartPoint(amount: p.amount, axisLabel: label, peakLabel: label);
  }).toList();
}

// Maps each backend category key to its legend/bar color, icon, and a
// short static subtitle. The subtitle text is descriptive copy only —
// not data from the server — same pattern as the color mapping below.
// NOTE: this switch only branches on 'membership' and 'day_pass' plus a
// catch-all — a real data-mapping gap, flagged before, still open.
=======
// Category key -> visual treatment. Add a case here whenever a new
// backend category key shows up; the catch-all keeps things rendering
// (just visually undifferentiated) instead of crashing.
>>>>>>> Stashed changes
Color _categoryColor(String category) {
  switch (category) {
    case 'membership':
      return AppColors.accentTeal;
    case 'day_pass':
      return AppColors.categoryTeal;
    case 'retail':
      return AppColors.categoryAmber;
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
            children: [
              const Text(
                'Sales Overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              const _LiveBadge(),
              const Spacer(),
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
            // View route below is a placeholder — point it at whatever
            // your full sales-log screen is actually called.
            data: (snapshot) => _SalesContent(
              snapshot: snapshot,
              range: range,
              onViewLog: () => context.push('/sales-log'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
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
            'Live',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.linkGreen,
            ),
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
  const _SalesContent({
    required this.snapshot,
    required this.range,
    required this.onViewLog,
  });

  final AnalyticsSnapshot snapshot;
  final String range;
  final VoidCallback onViewLog;

  String? _transactionsLabel(int? count) {
    if (count == null)
      return null; // backend hasn't sent this yet — hide the line
    switch (range) {
      case '1D':
        return '$count daily transactions recorded';
      case '1W':
        return '$count transactions recorded this week';
      case '1M':
      default:
        return '$count transactions recorded this month';
    }
  }

  @override
  Widget build(BuildContext context) {
    final changePct = snapshot.revenueChangePct;
<<<<<<< Updated upstream
    final chartPoints = _buildChartPoints(snapshot);
    final showAxisLabels = chartPoints.length <= 7;
=======
    final txLabel = _transactionsLabel(snapshot.transactionCount);
>>>>>>> Stashed changes

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
<<<<<<< Updated upstream
        const SizedBox(height: 22),
        SizedBox(
          height: showAxisLabels ? 210 : 190,
          child: chartPoints.length < 2
              ? const Center(
                  child: Text(
                    'Not enough data yet',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                )
              : _RevenueChart(points: chartPoints, showAxisLabels: showAxisLabels),
        ),
        const SizedBox(height: 18),
        _StatTileRow(breakdown: snapshot.breakdown),
        const SizedBox(height: 18),
        // -------------------------------------------------------------
        // REVENUE RATIO — back between the chart and the breakdown,
        // where the reference design has it. No "Category performance"
        // header anymore — removed per feedback.
        // -------------------------------------------------------------
        _RevenueRatio(breakdown: snapshot.breakdown),
        const SizedBox(height: 16),
        _BreakdownList(breakdown: snapshot.breakdown),
=======
        if (txLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            txLabel,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
        const SizedBox(height: 18),
        _ChartWithPeak(series: snapshot.series, range: range),
        const SizedBox(height: 18),
        _CategoryChipsRow(breakdown: snapshot.breakdown),
        const SizedBox(height: 18),
        if (range == '1D')
          _ActivityLogSection(
            activity: snapshot.recentActivity,
            onViewAll: onViewLog,
          )
        else
          _ViewSalesLogLink(onTap: onViewLog),
>>>>>>> Stashed changes
      ],
    );
  }
}

<<<<<<< Updated upstream
/// The revenue line chart plus a "₱X Peak (label)" bubble floated over
/// its highest point. Bubble position is computed as a fraction of the
/// chart's own plotted bounds (same minY/maxY passed to LineChartData),
/// so it lines up with the line regardless of chart size.
class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.points, required this.showAxisLabels});

  final List<_ChartPoint> points;
  final bool showAxisLabels;

  @override
  Widget build(BuildContext context) {
    var peakIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].amount > points[peakIndex].amount) peakIndex = i;
    }
    final peakAmount = points[peakIndex].amount;
    final maxY = peakAmount <= 0 ? 1.0 : peakAmount * 1.35;
    const minY = 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final xFraction = points.length == 1
            ? 0.5
            : peakIndex / (points.length - 1);
        final yFraction = maxY == minY ? 0.0 : 1 - (peakAmount - minY) / (maxY - minY);
        // Reserve room below for axis labels so the bubble is placed
        // relative to the plotted area, not the whole SizedBox.
        final plotHeight = constraints.maxHeight - (showAxisLabels ? 28 : 0);

        return Stack(
          children: [
            LineChart(
              LineChartData(
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  show: showAxisLabels,
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: showAxisLabels,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            points[i].axisLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.muted,
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
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].amount),
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
            Positioned(
              left: (constraints.maxWidth * xFraction - 62).clamp(
                0,
                constraints.maxWidth - 124,
              ),
              top: (plotHeight * yFraction - 40).clamp(0, plotHeight),
              child: IgnorePointer(
                child: _PeakBubble(
                  amount: peakAmount,
                  label: points[peakIndex].peakLabel,
                ),
              ),
            ),
          ],
        );
      },
=======
/// Line chart with a persistent "peak" callout — the bubble that sits
/// above the highest point on the reference screens, always visible
/// (not only on touch).
///
/// fl_chart auto-computes its own Y padding, which makes it impossible
/// to reliably back out pixel coordinates for an overlay. So minY/maxY
/// are pinned explicitly here and the overlay math reuses those exact
/// same bounds — that's what keeps the bubble glued to the real peak
/// dot instead of drifting.
class _ChartWithPeak extends StatelessWidget {
  const _ChartWithPeak({required this.series, required this.range});

  final List<RevenuePoint> series;
  final String range;

  static const _chartHeight = 200.0;
  static const _bottomAxisHeight = 28.0;
  static const _topClearance = 38.0;

  String _pointLabel(RevenuePoint p, int index) {
    switch (range) {
      case '1D':
        return DateFormat('h a').format(p.date);
      case '1W':
        return DateFormat('EEE').format(p.date);
      case '1M':
      default:
        return 'Week ${index + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) {
      return const SizedBox(
        height: _chartHeight,
        child: Center(
          child: Text(
            'Not enough data yet',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      );
    }

    final amounts = series.map((p) => p.amount).toList();
    final maxAmount = amounts.reduce((a, b) => a > b ? a : b);
    final peakIndex = amounts.indexOf(maxAmount);

    const chartMinY = 0.0;
    final chartMaxY = maxAmount <= 0 ? 1.0 : maxAmount * 1.28;
    final plotHeight = _chartHeight - _bottomAxisHeight - _topClearance;
    final labelInterval = (series.length / 5).ceil().clamp(1, series.length);

    return SizedBox(
      height: _chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = constraints.maxWidth;
          final xFrac = peakIndex / (series.length - 1);
          final yFrac = (maxAmount - chartMinY) / (chartMaxY - chartMinY);
          final peakLeft = xFrac * plotWidth;
          final peakTop = _topClearance + (1 - yFrac) * plotHeight;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: _topClearance),
                child: SizedBox(
                  height: plotHeight + _bottomAxisHeight,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (series.length - 1).toDouble(),
                      minY: chartMinY,
                      maxY: chartMaxY,
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: const AxisTitles(),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _bottomAxisHeight,
                            getTitlesWidget: (value, meta) {
                              final i = value.round();
                              final isLast = i == series.length - 1;
                              if (i < 0 ||
                                  i >= series.length ||
                                  (i % labelInterval != 0 && !isLast)) {
                                return const SizedBox.shrink();
                              }
                              final isPeak = i == peakIndex;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _pointLabel(series[i], i),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isPeak
                                        ? AppColors.accentTeal
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
                        // Fires continuously while dragging, not just on
                        // tap-down — this is what makes scrubbing across
                        // the line feel live rather than one-shot.
                        touchSpotThreshold: 24,
                        getTouchedSpotIndicator: (barData, spotIndexes) {
                          return spotIndexes.map((i) {
                            return TouchedSpotIndicatorData(
                              FlLine(
                                color: AppColors.accentTeal.withValues(
                                  alpha: 0.4,
                                ),
                                strokeWidth: 1.5,
                                dashArray: [4, 4],
                              ),
                              FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, bar, index) =>
                                    FlDotCirclePainter(
                                      radius: 5,
                                      color: AppColors.accentTeal,
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    ),
                              ),
                            );
                          }).toList();
                        },
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => AppColors.ink,
                          getTooltipItems: (spots) => spots.map((s) {
                            final i = s.x.round();
                            final label = (i >= 0 && i < series.length)
                                ? ' · ${_pointLabel(series[i], i)}'
                                : '';
                            return LineTooltipItem(
                              '${_formatPeso(s.y)}$label',
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
                            for (var i = 0; i < series.length; i++)
                              FlSpot(i.toDouble(), series[i].amount),
                          ],
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: AppColors.accentTeal,
                          barWidth: 3,
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, _) =>
                                spot.x.round() == peakIndex,
                            getDotPainter: (spot, percent, bar, index) =>
                                FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.white,
                                  strokeWidth: 2,
                                  strokeColor: AppColors.accentTeal,
                                ),
                          ),
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
              ),
              Positioned(
                left: (peakLeft - 62).clamp(
                  0.0,
                  (plotWidth - 124).clamp(0.0, plotWidth),
                ),
                top: (peakTop - 34).clamp(0.0, _chartHeight),
                child: IgnorePointer(
                  child: _PeakBubble(
                    amount: maxAmount,
                    label: _pointLabel(series[peakIndex], peakIndex),
                  ),
                ),
              ),
            ],
          );
        },
      ),
>>>>>>> Stashed changes
    );
  }
}

class _PeakBubble extends StatelessWidget {
  const _PeakBubble({required this.amount, required this.label});
<<<<<<< Updated upstream

=======
>>>>>>> Stashed changes
  final double amount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_formatPeso(amount)} Peak ($label)',
<<<<<<< Updated upstream
=======
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
>>>>>>> Stashed changes
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

<<<<<<< Updated upstream
/// Walk-ins / Members / Retail & POS summary row. Amounts come straight
/// from the existing breakdown categories the API already returns —
/// "Retail & POS" is 'event' + 'merch' combined for this summary only;
/// the detailed list below still shows them separately.
class _StatTileRow extends StatelessWidget {
  const _StatTileRow({required this.breakdown});
  final List<CategoryBreakdown> breakdown;

  double _amountFor(Iterable<String> categories) {
    return breakdown
        .where((b) => categories.contains(b.category))
        .fold<double>(0, (sum, b) => sum + b.amount);
  }

  @override
  Widget build(BuildContext context) {
    final walkIns = _amountFor(const ['day_pass']);
    final members = _amountFor(const ['membership']);
    final retailPos = _amountFor(const ['event', 'merch']);

    return Row(
      children: [
        Expanded(child: _StatTile(label: 'Walk-ins', amount: walkIns)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Members', amount: members)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Retail & POS', amount: retailPos)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.amount});
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            _formatPeso(amount),
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

/// Label + percentage-accounted-for line, with the proportional bar
/// underneath. "100% accounted" is a real computed sum of the
/// breakdown's own percentages, not a hardcoded string.
class _RevenueRatio extends StatelessWidget {
  const _RevenueRatio({required this.breakdown});
=======
/// The Walk-ins / Members / Retail & POS row. Order + labels come
/// straight from `snapshot.breakdown` — nothing here is fixed to a
/// particular category beyond how it's colored.
class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({required this.breakdown});
>>>>>>> Stashed changes
  final List<CategoryBreakdown> breakdown;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < breakdown.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _CategoryChip(item: breakdown[i])),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.item});
  final CategoryBreakdown item;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(item.category);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.categoryChipBg,
        borderRadius: BorderRadius.circular(14),
        border: Border(top: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatPeso(item.amount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (item.count != null && item.countLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              '${item.count} ${item.countLabel}',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Today's Activity Log" — 1D range only. Backed entirely by
/// `snapshot.recentActivity`; render nothing if the repository hasn't
/// populated it (e.g. for non-1D ranges).
class _ActivityLogSection extends StatelessWidget {
  const _ActivityLogSection({required this.activity, required this.onViewAll});

  final List<RecentActivity> activity;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  "Today's Activity Log",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.fieldBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${activity.length} Latest',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: onViewAll,
              child: const Text(
                'View All →',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentTeal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < activity.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ActivityRow(item: activity[i]),
        ],
      ],
    );
  }
}

/// Retail line items (no person to initial) get an icon avatar; member
/// and walk-in activity get initials. Add cases here as your backend's
/// `type` values grow.
IconData? _activityIcon(String type) {
  switch (type) {
    case 'retail':
      return Icons.shopping_bag_outlined;
    default:
      return null; // member / walk_in -> initials avatar
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final RecentActivity item;

  String get _initials {
    final parts = item.title.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final icon = _activityIcon(item.type);
    final hasIcon = icon != null;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: hasIcon ? AppColors.fieldBg : AppColors.accentTealBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: hasIcon
              ? Icon(icon, size: 16, color: AppColors.muted)
              : Text(
                  _initials,
                  style: const TextStyle(
                    fontSize: 12,
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
        Text(
          _formatPeso(item.amount),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// 1W / 1M ranges show a link to the full log instead of the inline
/// activity list — matches the reference screens for those two ranges.
class _ViewSalesLogLink extends StatelessWidget {
  const _ViewSalesLogLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(
          Icons.receipt_long_outlined,
          size: 16,
          color: AppColors.accentTeal,
        ),
        label: const Text(
          'View Sales Log',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.accentTeal,
          ),
        ),
      ),
    );
  }
}
