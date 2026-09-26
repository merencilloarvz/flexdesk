import 'package:flexdesk/core/db/app_database.dart';
import 'package:flexdesk/features/checkin/check_in_screen.dart';
import 'package:flutter_test/flutter_test.dart';

MembershipPlan _plan(int centavos) => MembershipPlan(
  id: 'p',
  gymId: 'g',
  name: 'Day pass',
  category: 'Regular',
  durationValue: 1,
  durationUnit: 'DAY',
  priceCentavos: centavos,
  isDayPass: true,
  isActive: true,
  sortOrder: 0,
  updatedAt: DateTime.utc(2026, 1, 1),
  isDirty: false,
);

void main() {
  group('walkInButtonLabel', () {
    test('says what is missing, in order', () {
      expect(
        walkInButtonLabel(
          submitting: false,
          guestName: '  ',
          selectedPlan: null,
        ),
        'Enter a guest name',
      );
      expect(
        walkInButtonLabel(
          submitting: false,
          guestName: 'Ana',
          selectedPlan: null,
        ),
        'Pick a rate',
      );
    });

    test('shows the amount when ready', () {
      expect(
        walkInButtonLabel(
          submitting: false,
          guestName: 'Ana',
          selectedPlan: _plan(8000),
        ),
        'Check in · ₱80',
      );
      expect(
        walkInButtonLabel(
          submitting: false,
          guestName: 'Ana',
          selectedPlan: _plan(8050),
        ),
        'Check in · ₱80.50',
      );
    });
  });

  group('formatCheckInTime uses gym time, not the phone clock', () {
    // 23:30 UTC on Sep 25 is 7:30 AM Sep 26 in Manila.
    final checkedIn = DateTime.utc(2026, 9, 25, 23, 30);

    test('clock time is Manila time', () {
      expect(
        formatCheckInTime(checkedIn, now: DateTime.utc(2026, 9, 26, 5)),
        '7:30 AM',
      );
    });

    test('evening check-in reads as PM in Manila', () {
      // 11:57 UTC == 7:57 PM Manila.
      expect(
        formatCheckInTime(
          DateTime.utc(2026, 9, 25, 11, 57),
          now: DateTime.utc(2026, 9, 25, 20),
        ),
        '7:57 PM',
      );
    });

    test('recent check-ins are relative', () {
      final now = DateTime.utc(2026, 9, 25, 12);
      expect(formatCheckInTime(now, now: now), 'Just now');
      expect(
        formatCheckInTime(now.subtract(const Duration(minutes: 12)), now: now),
        '12m ago',
      );
    });
  });
}
