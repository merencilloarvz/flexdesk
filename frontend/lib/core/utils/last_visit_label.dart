import 'package:intl/intl.dart';

import 'gym_time.dart';

/// "Today" / "Yesterday" / "3 days ago" / "Sep 12" for a member's most
/// recent check-in, or "None yet".
///
/// [checkedInAt] is a real UTC instant, so the calendar day it falls on is
/// worked out in the gym's timezone (via [GymTime.toGymLocal]) and compared
/// with [today] (which must also be a gym-local date, e.g. `GymTime.today()`)
/// — never the phone's own timezone, which would call a 7am Manila check-in
/// "yesterday" for anyone whose phone is set elsewhere.
String lastVisitLabel(DateTime? checkedInAt, DateTime today) {
  if (checkedInAt == null) return 'None yet';
  final gymLocal = GymTime.toGymLocal(checkedInAt);
  final visitDay = DateTime(gymLocal.year, gymLocal.month, gymLocal.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final daysAgo = todayDay.difference(visitDay).inDays;
  if (daysAgo <= 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return '$daysAgo days ago';
  return DateFormat('MMM d').format(visitDay);
}
