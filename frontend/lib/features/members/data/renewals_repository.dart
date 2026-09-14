import 'members_api.dart';

/// One row of the Phase 5 renewal worklist — GET /members/expiring/'s
/// response shape. current_plan_category (not a plan name) matches
/// what the serializer actually returns and what every other "plan"
/// label in the app already shows.
class ExpiringMember {
  const ExpiringMember({
    required this.id,
    required this.fullName,
    required this.memberCode,
    required this.phone,
    required this.currentPlanCategory,
    required this.currentEndDate,
    required this.daysRemaining,
    required this.reminderContactedAt,
    required this.reminderContactedBy,
  });

  final String id;
  final String fullName;
  final String memberCode;
  final String phone;
  final String? currentPlanCategory;
  final DateTime? currentEndDate;
  final int? daysRemaining;
  final DateTime? reminderContactedAt;
  final String? reminderContactedBy;

  bool get hasReminder => reminderContactedAt != null;

  factory ExpiringMember.fromJson(Map<String, dynamic> json) {
    final reminder = json['reminder'] as Map<String, dynamic>?;
    return ExpiringMember(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      memberCode: json['member_code'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      currentPlanCategory: json['current_plan_category'] as String?,
      currentEndDate: json['current_end_date'] != null
          ? DateTime.parse(json['current_end_date'] as String)
          : null,
      daysRemaining: json['days_remaining'] as int?,
      reminderContactedAt: reminder?['contacted_at'] != null
          ? DateTime.parse(reminder!['contacted_at'] as String)
          : null,
      reminderContactedBy: reminder?['contacted_by'] as String?,
    );
  }
}

/// Phase 5 Part B. Deliberately never touches Drift — this is derived,
/// daily-changing server state (B4), not something to cache locally.
/// Every read is a live fetch; every write (remind) is followed by the
/// caller re-fetching rather than patching a row in place, which is
/// what "no optimistic UI on Mark as contacted" (standing rule 12)
/// actually means in practice here.
class RenewalsRepository {
  RenewalsRepository(this._api);

  final MembersApi _api;

  Future<List<ExpiringMember>> fetchExpiring() async {
    final rows = await _api.fetchExpiringMembers();
    return _sorted(rows.map(ExpiringMember.fromJson).toList());
  }

  Future<void> markContacted(String memberId, {String? note}) async {
    await _api.remindMember(memberId, note: note);
  }

  /// Soonest end date first (B1); within the same end date, uncontacted
  /// rows before contacted ones (B1's "sorted below... within the same
  /// day"). The server already orders by (current_end_date, id) —
  /// indexing before sorting and using that index as the final
  /// tiebreaker preserves that relative order deterministically,
  /// since List.sort in Dart isn't guaranteed stable.
  List<ExpiringMember> _sorted(List<ExpiringMember> rows) {
    final indexed = rows.asMap().entries.toList();
    indexed.sort((a, b) {
      final aDate = a.value.currentEndDate;
      final bDate = b.value.currentEndDate;
      final dateCompare = (aDate ?? DateTime(0)).compareTo(bDate ?? DateTime(0));
      if (dateCompare != 0) return dateCompare;
      if (a.value.hasReminder != b.value.hasReminder) {
        return a.value.hasReminder ? 1 : -1;
      }
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }
}
