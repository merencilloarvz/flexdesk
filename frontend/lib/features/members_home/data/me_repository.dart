import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'me_api.dart';

/// Parsed shape of a `/me/summary/` response.
///
/// Deliberately does NOT carry `membership_status` or `days_remaining`
/// from the server — both are computed at request time and go stale the
/// moment this gets cached. `currentEndDate` is the fact; the caller
/// derives status/days-remaining from it locally via `statusFor()` /
/// `daysRemaining()` against `GymTime.today()`, the same helpers the
/// owner app uses. That's what keeps a cached-on-Monday, viewed-on-
/// Thursday screen from silently showing a stale countdown.
class MeSummary {
  const MeSummary({
    required this.id,
    required this.fullName,
    required this.memberCode,
    required this.currentEndDate,
    required this.currentPlanCategory,
    required this.isArchived,
    required this.gymName,
    required this.gymTimezone,
    required this.gymCurrency,
    required this.checkInsThisMonth,
    required this.lastCheckInAt,
  });

  final String id;
  final String fullName;
  final String memberCode;
  final DateTime? currentEndDate;
  final String? currentPlanCategory;
  final bool isArchived;
  final String gymName;
  final String gymTimezone;
  final String gymCurrency;
  final int checkInsThisMonth;
  final DateTime? lastCheckInAt;

  factory MeSummary.fromJson(Map<String, dynamic> json) {
    final gym = json['gym'] as Map<String, dynamic>? ?? const {};
    return MeSummary(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      memberCode: json['member_code'] as String? ?? '',
      currentEndDate: json['current_end_date'] != null
          ? DateTime.parse(json['current_end_date'] as String)
          : null,
      currentPlanCategory: json['current_plan_category'] as String?,
      isArchived: json['is_archived'] as bool? ?? false,
      gymName: gym['name'] as String? ?? '',
      gymTimezone: gym['timezone'] as String? ?? 'Asia/Manila',
      gymCurrency: gym['currency'] as String? ?? 'PHP',
      checkInsThisMonth: json['check_ins_this_month'] as int? ?? 0,
      lastCheckInAt: json['last_check_in_at'] != null
          ? DateTime.parse(json['last_check_in_at'] as String)
          : null,
    );
  }
}

/// A summary paired with when it was fetched — the "last updated" label
/// on the home screen reads [fetchedAt] directly.
class CachedMeSummary {
  const CachedMeSummary({required this.summary, required this.fetchedAt});

  final MeSummary summary;
  final DateTime fetchedAt;
}

/// One page of a paginated /me/ list endpoint.
class MePage<T> {
  const MePage({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;
}

/// Online-first, deliberately without a Drift table or a sync queue — see
/// Stage 4.3b's architecture note. The member app can wait for a
/// connection; the one caching exception is the summary blob, kept as a
/// single JSON file so the home screen isn't blank on a cold offline
/// start. Nothing here goes in secure storage: everything cached is
/// re-derivable from the server, which is exactly what secure storage is
/// for NOT holding.
class MeRepository {
  MeRepository(this._api);

  final MeApi _api;

  static const _cacheFileName = 'me_summary_cache.json';

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  /// Reads the last cached summary, or null if there isn't one or it's
  /// unreadable. A corrupt cache file is treated as "no cache" — never
  /// thrown — since this is only ever a convenience layer over the real
  /// source of truth (the server).
  Future<CachedMeSummary?> readCachedSummary() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final summaryJson = decoded['summary'] as Map<String, dynamic>;
      final fetchedAt = DateTime.parse(decoded['fetched_at'] as String);
      return CachedMeSummary(
        summary: MeSummary.fromJson(summaryJson),
        fetchedAt: fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(Map<String, dynamic> summaryJson) async {
    try {
      final file = await _cacheFile();
      final payload = jsonEncode({
        'summary': summaryJson,
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      });
      await file.writeAsString(payload);
    } catch (_) {
      // Best-effort — a failed cache write must never break the fetch
      // that triggered it.
    }
  }

  /// Fetches the current summary from the server and updates the cache.
  /// Throws (ApiException) on failure — callers decide what "failure
  /// with a cache already showing" versus "failure with nothing to show"
  /// means for their UI.
  Future<MeSummary> refreshSummary() async {
    final json = await _api.fetchSummary();
    await _writeCache(json);
    return MeSummary.fromJson(json);
  }

  Future<MePage<Map<String, dynamic>>> fetchMembershipPage(int page) async {
    final body = await _api.fetchMembershipPage(page);
    return MePage(
      items: (body['results'] as List).cast<Map<String, dynamic>>(),
      hasMore: body['next'] != null,
    );
  }

  Future<MePage<Map<String, dynamic>>> fetchCheckInsPage(int page) async {
    final body = await _api.fetchCheckInsPage(page);
    return MePage(
      items: (body['results'] as List).cast<Map<String, dynamic>>(),
      hasMore: body['next'] != null,
    );
  }
}
