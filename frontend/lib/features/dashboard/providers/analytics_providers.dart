import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/analytics_api.dart';

const List<String> analyticsRanges = ['1D', '1W', '1M', '3M'];

final analyticsRangeProvider = StateProvider<String>((ref) => '1M');

final analyticsApiProvider = Provider<AnalyticsApi>((ref) {
  return AnalyticsApi(ref.watch(dioProvider));
});

class RevenuePoint {
  const RevenuePoint({required this.date, required this.amount});
  final DateTime date;
  final double amount;
}

class CategoryBreakdown {
  const CategoryBreakdown({
    required this.category,
    required this.label,
    required this.amount,
    required this.pct,
  });
  final String category;
  final String label;
  final double amount;
  final double pct;
}

class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.range,
    required this.revenueTotal,
    required this.revenueChangePct,
    required this.series,
    required this.breakdown,
    required this.checkInsToday,
    required this.checkInsYesterday,
    required this.checkInsChangePct,
  });

  final String range;
  final double revenueTotal;
  final double? revenueChangePct;
  final List<RevenuePoint> series;
  final List<CategoryBreakdown> breakdown;
  final int checkInsToday;
  final int checkInsYesterday;
  final double? checkInsChangePct;

  factory AnalyticsSnapshot.fromJson(Map<String, dynamic> json) {
    final revenue = json['revenue'] as Map<String, dynamic>;
    final checkIns = json['check_ins'] as Map<String, dynamic>;

    return AnalyticsSnapshot(
      range: json['range'] as String,
      revenueTotal: double.parse(revenue['total'] as String),
      revenueChangePct: (revenue['change_pct'] as num?)?.toDouble(),
      series: (revenue['series'] as List).map((p) {
        final m = p as Map<String, dynamic>;
        return RevenuePoint(
          date: DateTime.parse(m['date'] as String),
          amount: double.parse(m['amount'] as String),
        );
      }).toList(),
      breakdown: (revenue['breakdown'] as List).map((b) {
        final m = b as Map<String, dynamic>;
        return CategoryBreakdown(
          category: m['category'] as String,
          label: m['label'] as String,
          amount: double.parse(m['amount'] as String),
          pct: (m['pct'] as num).toDouble(),
        );
      }).toList(),
      checkInsToday: checkIns['today'] as int,
      checkInsYesterday: checkIns['yesterday'] as int,
      checkInsChangePct: (checkIns['change_pct'] as num?)?.toDouble(),
    );
  }
}

final analyticsProvider =
    FutureProvider.family<AnalyticsSnapshot, ({String gymId, String range})>((
      ref,
      args,
    ) async {
      final api = ref.watch(analyticsApiProvider);
      final json = await api.fetchAnalytics(args.range);
      return AnalyticsSnapshot.fromJson(json);
    });
