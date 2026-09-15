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
            data: (snapshot) => _SalesContent(snapshot: snapshot, range: range),
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
  const _SalesContent({required this.snapshot, required this.range});

  final AnalyticsSnapshot snapshot;
  final String range;

  String? _transactionsLabel(int? count) {
    if (count == null) {
      return null; // backend hasn't sent this yet — hide the line
    }
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
    final txLabel = _transactionsLabel(snapshot.transactionCount);

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
        _StatTileRow(breakdown: snapshot.breakdown),
      ],
    );
  }
}

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

  /// 1M has ~30 daily points from the API — too dense for "Week N"
  /// labels to mean anything, so they're bucketed into 7-day chunks
  /// here purely for display. 1D/1W are returned unchanged: the API
  /// already gives them at the granularity the labels expect (hourly*
  /// and daily respectively; *pending backend hourly support for 1D).
  List<RevenuePoint> get _displaySeries {
    if (range != '1M' || series.length <= 7) return series;
    final buckets = <RevenuePoint>[];
    for (var start = 0; start < series.length; start += 7) {
      final end = (start + 7 < series.length) ? start + 7 : series.length;
      final chunk = series.sublist(start, end);
      final sum = chunk.fold<double>(0, (s, p) => s + p.amount);
      buckets.add(RevenuePoint(date: chunk.last.date, amount: sum));
    }
    return buckets;
  }

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
    final series = _displaySeries;

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
    );
  }
}

class _PeakBubble extends StatelessWidget {
  const _PeakBubble({required this.amount, required this.label});
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Walk-ins / Members / Retail & POS summary row. Amounts come straight
/// from the existing breakdown categories the API already returns —
/// "Retail & POS" is 'event' + 'merch' combined for this summary only.
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
