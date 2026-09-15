import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/analytics_api.dart';

const activityLogLimit = 5;

const List<String> analyticsRanges = ['1D', '1W', '1M'];

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
    this.count,
    this.countLabel,
  });
  final String category;
  final String label;
  final double amount;
  final double pct;

  // Optional — populate from the backend when it can tell you "46
  // guests" / "8 renewals" / "179 items". Null hides the subtitle.
  final int? count;
  final String? countLabel;
}

/// One row in "Today's Activity Log" (1D range). [type] drives which
/// icon/avatar the UI shows — kept as a plain string here so this model
/// stays UI-agnostic.
class RecentActivity {
  const RecentActivity({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
  });

  final String title;
  final String subtitle;
  final double amount;

  /// 'member' | 'walk_in' | 'retail' | ... — whatever your backend uses
  /// to tag the sale. Falls back to 'other' if missing.
  final String type;
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
    this.transactionCount,
    this.recentActivity = const [],
  });

  final String range;
  final double revenueTotal;
  final double? revenueChangePct;
  final List<RevenuePoint> series;
  final List<CategoryBreakdown> breakdown;
  final int checkInsToday;
  final int checkInsYesterday;
  final double? checkInsChangePct;

  // Optional — both null/empty until the backend sends them. The card
  // hides the pieces that depend on these rather than showing zeros.
  final int? transactionCount;
  final List<RecentActivity> recentActivity;

  factory AnalyticsSnapshot.fromJson(Map<String, dynamic> json) {
    final revenue = json['revenue'] as Map<String, dynamic>;
    final checkIns = json['check_ins'] as Map<String, dynamic>;

    return AnalyticsSnapshot(
      range: json['range'] as String,
      revenueTotal: double.parse(revenue['total'] as String),
      revenueChangePct: (revenue['change_pct'] as num?)?.toDouble(),
      transactionCount: (revenue['transaction_count'] as num?)?.toInt(),
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
          count: (m['count'] as num?)?.toInt(),
          countLabel: m['count_label'] as String?,
        );
      }).toList(),
      recentActivity: ((revenue['recent_activity'] as List?) ?? []).map((a) {
        final m = a as Map<String, dynamic>;
        return RecentActivity(
          title: m['title'] as String,
          subtitle: m['subtitle'] as String,
          amount: double.parse(m['amount'].toString()),
          type: m['type'] as String? ?? 'other',
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

/// One row in "Today's Activity Log". [type] drives which icon/avatar
/// the UI shows — kept as a plain string here so this model stays
/// UI-agnostic; 'walk_in' | 'member' | 'retail' from the backend today.
class RecentActivity {
  const RecentActivity({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final String type;
  final String title;
  final String subtitle;
  final double amount;

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      type: json['type'] as String? ?? 'other',
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      amount: double.parse(json['amount'].toString()),
    );
  }
}

/// Always "today" for the gym, regardless of the Sales Overview range
/// toggle — same as the check-ins badge on [AnalyticsSnapshot].
final activityLogProvider =
    FutureProvider.family<List<RecentActivity>, String>((ref, gymId) async {
      final api = ref.watch(analyticsApiProvider);
      final json = await api.fetchActivityLog(limit: activityLogLimit);
      final activities = json['activities'] as List;
      return activities
          .map((a) => RecentActivity.fromJson(a as Map<String, dynamic>))
          .toList();
    });
