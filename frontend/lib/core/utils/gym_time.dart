/// Computes "today" the same way the backend does.
///
/// MUST MATCH `gym_today()` in `backend/core/utils.py`:
/// ```python
/// def gym_today(gym):
///     return timezone.now().astimezone(ZoneInfo(gym.timezone)).date()
/// ```
/// The backend converts the current instant into the *gym's* timezone and
/// takes the date there — not the UTC date. If this ever drifts from the
/// backend, the status badge computed here and the `days_remaining` value
/// the server sent will contradict each other on the same screen, most
/// visibly from ~4pm local time onward when the UTC date is still
/// "yesterday".
///
/// The `timezone` package isn't a project dependency, and Asia/Manila is a
/// fixed UTC+8 with no DST, so a constant offset stands in for a real
/// timezone conversion. This is a stopgap: if a gym is ever created with a
/// `timezone` other than Asia/Manila, this needs the real `timezone`
/// package (looking up the offset per `gym.timezone`) instead of a bare
/// constant. Kept in one place so that day comes with one edit, not a
/// grep-and-replace.
class GymTime {
  GymTime._();

  /// Fixed UTC+8 offset for Asia/Manila, the only gym timezone in use today.
  static const Duration _gymOffset = Duration(hours: 8);

  /// Today's date in the gym's local timezone, as a date-only [DateTime]
  /// (midnight, no time component) — matching Python's `.date()`.
  static DateTime today() {
    final gymNow = DateTime.now().toUtc().add(_gymOffset);
    return DateTime(gymNow.year, gymNow.month, gymNow.day);
  }

  /// The real UTC instant that marks the START of [gymLocalDay] (a
  /// date-only value, e.g. from `today()`) in the gym's local timezone.
  ///
  /// Built with `DateTime.utc(...)` rather than the device's local
  /// `DateTime(...)` constructor so this never depends on what timezone
  /// the phone itself is set to — only on the gym's fixed +8 offset.
  ///
  /// Use this (never a naive `DateTime(y, m, d)`) whenever comparing
  /// against `checkedInAt`, which is always stored as a real UTC instant.
  /// Comparing a naive local-calendar date against a UTC timestamp is
  /// comparing two different clocks — it silently drifts by a day right
  /// around midnight.
  static DateTime startOfDay(DateTime gymLocalDay) {
    final utcMidnightOfThatCalendarDate = DateTime.utc(
      gymLocalDay.year,
      gymLocalDay.month,
      gymLocalDay.day,
    );
    return utcMidnightOfThatCalendarDate.subtract(_gymOffset);
  }

  /// The UTC instant marking the START of the NEXT gym-local day — i.e.
  /// the exclusive upper bound for "this day". Pair with [startOfDay] for
  /// a `>= start AND < end` range query.
  static DateTime endOfDay(DateTime gymLocalDay) {
    return startOfDay(gymLocalDay).add(const Duration(days: 1));
  }
}
