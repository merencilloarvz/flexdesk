enum MembershipStatus { noMembership, expired, expiring, active }

/// Strips the time component so date comparisons don't depend on what time
/// of day the caller happened to run them. `endDate` from `DateTime.parse`
/// on a date-only string is already midnight, but `today` is normally
/// `DateTime.now()` — which carries a real clock time and would otherwise
/// make a membership look expired hours before its actual last valid day.
DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Mirrors `Member.with_status()` on the backend exactly — there is no
/// server-side ambiguity here, so this local derivation is safe to trust.
///
/// `today` MUST be computed in `gym.timezone` (Asia/Manila, UTC+8), never
/// UTC or the device locale. From 4pm local onward, a UTC-based "today" is
/// a day behind and every days-remaining value is off by one all evening.
///
/// `end_date` is inclusive on the backend (`start + delta - 1 day`), so a
/// membership ending today is still active — that's why the boundary check
/// below is `!isAfter(today + expiringWithin)`, not a plain comparison.
/// Getting this wrong shows a member as expired on their last paid day, at
/// the front desk, in front of them.
///
/// Both dates are normalized to midnight internally, so it's safe to pass
/// `DateTime.now()` directly as `today` — callers don't need to strip the
/// time themselves.
MembershipStatus statusFor(
  DateTime? endDate,
  DateTime today, {
  // Must match the `expiring_within_days` default at the server's
  // queryset call site in views.py — check that call site if this ever
  // needs to change, don't just edit the default here in isolation.
  int expiringWithin = 7,
}) {
  if (endDate == null) return MembershipStatus.noMembership;
  final end = _dateOnly(endDate);
  final now = _dateOnly(today);
  if (end.isBefore(now)) return MembershipStatus.expired;
  if (!end.isAfter(now.add(Duration(days: expiringWithin)))) {
    return MembershipStatus.expiring;
  }
  return MembershipStatus.active;
}

/// `0` means the last valid day, not expired — same inclusive-end_date
/// reasoning as [statusFor]. Both dates are normalized to midnight first,
/// so this is stable no matter what time of day `today` is passed as.
int? daysRemaining(DateTime? endDate, DateTime today) {
  if (endDate == null) return null;
  return _dateOnly(endDate).difference(_dateOnly(today)).inDays;
}
