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

  /// The current wall-clock instant in the gym's local timezone, as a
  /// naive [DateTime] (same "local-flavored" construction as [today], just
  /// with the time-of-day fields kept instead of zeroed). For comparisons
  /// that need to know whether a specific time today has passed — [today]
  /// alone can't answer that, since it collapses to midnight.
  static DateTime now() => nowAt(DateTime.now());

  /// [now] for an explicit instant, so callers (and tests) can pin the
  /// clock. Independent of the device's timezone.
  static DateTime nowAt(DateTime instant) {
    final gymNow = instant.toUtc().add(_gymOffset);
    return DateTime(
      gymNow.year,
      gymNow.month,
      gymNow.day,
      gymNow.hour,
      gymNow.minute,
      gymNow.second,
    );
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

  /// Converts a real UTC instant (e.g. `checkedInAt`) into the gym's local
  /// wall-clock time, for DISPLAY only — showing a date/time to a person,
  /// never for date-range comparisons against stored UTC instants (use
  /// [startOfDay]/[endOfDay] for that; comparing a converted-then-naive
  /// value against a UTC timestamp reintroduces the same drift bug this
  /// class exists to prevent).
  ///
  /// The returned DateTime's fields (hour, day, month...) are correct for
  /// display, but its `.isUtc` flag stays true — don't feed this into
  /// further UTC-instant comparisons.
  static DateTime toGymLocal(DateTime utcInstant) {
    return utcInstant.toUtc().add(_gymOffset);
  }

  /// Parses a server timestamp into a naive gym-local [DateTime].
  ///
  /// Strings carrying an offset or `Z` (e.g. `2026-09-25T19:00:00+08:00`)
  /// are real instants: `DateTime.parse` turns them into UTC, whose
  /// fields read 11:00 — 8 hours off on a gym-local label. They're
  /// converted via [toGymLocal]. Date-only strings (`2026-09-25`) are
  /// already gym-local calendar dates and pass through unchanged.
  static DateTime parseGymLocal(String iso) {
    final parsed = DateTime.parse(iso);
    if (!parsed.isUtc && !RegExp(r'[Zz]|[+-]\d\d:?\d\d$').hasMatch(iso)) {
      return parsed;
    }
    final g = toGymLocal(parsed);
    return DateTime(g.year, g.month, g.day, g.hour, g.minute, g.second);
  }

  /// "Good morning" / "afternoon" / "evening" for a gym-local wall-clock
  /// time (pass [now] / [nowAt], never a raw `DateTime.now()`).
  static String greetingFor(DateTime gymLocal) {
    final h = gymLocal.hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }
}
