import 'package:flexdesk/core/utils/gym_time.dart';
import 'package:flexdesk/features/dashboard/providers/analytics_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-09-25 19:57 in Manila == 2026-09-25 11:57 UTC. Use a moment where
  // the halves of the day differ AND the dates differ:
  // 2026-09-25 23:30 UTC == 2026-09-26 07:30 Manila.
  final utcLateNight = DateTime.utc(2026, 9, 25, 23, 30);
  final utcNoon = DateTime.utc(2026, 9, 25, 11, 57);

  group('greeting', () {
    test('7:57 PM Manila is evening even though UTC says morning', () {
      expect(GymTime.greetingFor(GymTime.nowAt(utcNoon)), 'Good evening');
    });

    test('7:30 AM Manila is morning even though UTC says 11:30 PM', () {
      final gym = GymTime.nowAt(utcLateNight);
      expect(gym.day, 26); // next calendar day in Manila
      expect(GymTime.greetingFor(gym), 'Good morning');
    });

    test('boundaries', () {
      expect(GymTime.greetingFor(DateTime(2026, 1, 1, 11, 59)), 'Good morning');
      expect(GymTime.greetingFor(DateTime(2026, 1, 1, 12)), 'Good afternoon');
      expect(GymTime.greetingFor(DateTime(2026, 1, 1, 18)), 'Good evening');
    });
  });

  group('parseGymLocal', () {
    test('offset timestamp keeps gym-local hour', () {
      final d = GymTime.parseGymLocal('2026-09-25T19:00:00+08:00');
      expect((d.day, d.hour), (25, 19));
    });

    test('Z timestamp converts to +8', () {
      final d = GymTime.parseGymLocal('2026-09-25T23:30:00Z');
      expect((d.day, d.hour, d.minute), (26, 7, 30));
    });

    test('date-only passes through', () {
      final d = GymTime.parseGymLocal('2026-09-25');
      expect((d.day, d.hour), (25, 0));
    });
  });

  test('1D hourly series from the backend buckets in gym hours', () {
    final snap = AnalyticsSnapshot.fromJson({
      'range': '1D',
      'revenue': {
        'total': '0.00',
        'series': [
          {'date': '2026-09-25T00:00:00+08:00', 'amount': '0.00'},
          {'date': '2026-09-25T18:00:00+08:00', 'amount': '50.00'},
          {'date': '2026-09-25T19:00:00+08:00', 'amount': '0.00'},
        ],
        'breakdown': [],
      },
      'check_ins': {'today': 0, 'yesterday': 0},
    });
    expect(snap.series.map((p) => p.date.hour), [0, 18, 19]);
    expect(snap.series.every((p) => p.date.day == 25), isTrue);
  });

  test('day boundaries: 7 AM Manila check-in belongs to the Manila day', () {
    final checkIn = utcLateNight; // 07:30 Sep 26 Manila
    final manilaDay = DateTime(2026, 9, 26);
    expect(checkIn.isBefore(GymTime.startOfDay(manilaDay)), isFalse);
    expect(checkIn.isBefore(GymTime.endOfDay(manilaDay)), isTrue);
    expect(GymTime.startOfDay(manilaDay), DateTime.utc(2026, 9, 25, 16));
  });
}
