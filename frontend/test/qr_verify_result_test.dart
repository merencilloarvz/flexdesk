// Phase 3b C1 fix — the confirmation sheet now renders entirely from
// verify-qr's own response, not a local Member lookup. This proves
// QrVerifyResult carries everything that path needs (the id for
// createMemberCheckIn, and every display field the sheet shows)
// straight from the JSON body — no local Drift row for this member
// needs to exist for the data to be complete and usable.
import 'package:flutter_test/flutter_test.dart';

import 'package:flexdesk/features/checkin/qr_scanner_screen.dart';

// Adjust the `package:flexdesk/...` import above if your pubspec's
// `name:` isn't `flexdesk` — same note as db_smoke_test.dart.

void main() {
  group('QrVerifyResult.fromJson', () {
    test(
      'a verify-qr response for a member absent from the local cache '
      'still parses into a fully usable confirmation path',
      () {
        // Shape returned by CheckInViewSet.verify_qr — nothing here
        // depends on this member ever having synced to this device.
        final result = QrVerifyResult.fromJson({
          'id': 'member-not-in-local-cache',
          'full_name': 'Ana Reyes',
          'member_code': 'M-1042',
          'membership_status': 'expiring',
          'current_end_date': '2026-09-20',
          'days_remaining': 5,
          'already_checked_in_today': false,
        });

        // What createMemberCheckIn needs.
        expect(result.memberId, 'member-not-in-local-cache');
        expect(result.membershipStatus, 'expiring');
        expect(result.currentEndDate, DateTime.parse('2026-09-20'));

        // What the confirmation sheet displays.
        expect(result.fullName, 'Ana Reyes');
        expect(result.memberCode, 'M-1042');
        expect(result.daysRemaining, 5);
        expect(result.alreadyCheckedInToday, isFalse);
      },
    );

    test('a null current_end_date and days_remaining parse safely', () {
      final result = QrVerifyResult.fromJson({
        'id': 'member-2',
        'full_name': 'Carlos Cruz',
        'member_code': 'M-2001',
        'membership_status': 'no_membership',
        'current_end_date': null,
        'days_remaining': null,
        'already_checked_in_today': true,
      });

      expect(result.currentEndDate, isNull);
      expect(result.daysRemaining, isNull);
      expect(result.alreadyCheckedInToday, isTrue);
    });
  });
}
