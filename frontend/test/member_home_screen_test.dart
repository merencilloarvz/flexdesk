import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flexdesk/core/utils/gym_time.dart';
import 'package:flexdesk/core/utils/last_visit_label.dart';
import 'package:flexdesk/features/auth/providers/auth_providers.dart';
import 'package:flexdesk/features/community/data/community_api.dart';
import 'package:flexdesk/features/community/data/community_repository.dart';
import 'package:flexdesk/features/community/providers/community_providers.dart';
import 'package:flexdesk/features/members_home/providers/member_stats_provider.dart';
import 'package:flexdesk/features/members_home/screens/member_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

DateTime _today() => GymTime.today();

String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

Map<String, dynamic> _eventJson(
  String id, {
  required DateTime date,
  String? startTime,
  bool canceled = false,
  String fee = '0.00',
}) => {
  'id': id,
  'title': id, // the tests find events by their id-as-title
  'description': '',
  'event_date': _dateStr(date),
  'start_time': startTime,
  'location_text': 'Main Floor',
  'registration_fee': fee,
  'canceled_at': canceled ? '2026-01-01T00:00:00Z' : null,
  'like_count': 0,
  'liked_by_me': false,
  'comment_count': 0,
};

Event _event(
  String id, {
  required DateTime date,
  String? startTime,
  bool canceled = false,
}) => Event.fromJson(
  _eventJson(id, date: date, startTime: startTime, canceled: canceled),
);

class _FakeApi implements CommunityApi {
  _FakeApi(this.events);
  final List<Map<String, dynamic>> events;
  bool failEvents = false;

  @override
  Future<List<Map<String, dynamic>>> fetchEvents() async {
    if (failEvents) {
      throw ApiException(kind: ApiExceptionKind.network, message: 'offline');
    }
    return events;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth extends AuthController {
  _FakeAuth(this.user);
  final AuthUser user;
  @override
  AuthState build() => AuthAuthenticated(user);
}

AuthUser _member({required bool classesEnabled}) => AuthUser(
  id: 'u1',
  email: 'ana@example.com',
  fullName: 'Ana Cruz',
  defaultLocationId: null,
  role: UserRole.unknown,
  accountType: 'member',
  mustChangePassword: false,
  hasSeenOwnerWelcome: false,
  gym: Gym(
    id: 'g1',
    name: 'Iron Works',
    timezone: 'Asia/Manila',
    currency: 'PHP',
    needsSetup: false,
    classesEnabled: classesEnabled,
    subscriptionStatus: null,
    subscriptionBlocked: false,
    trialEndsAt: null,
    currentPeriodEnd: null,
    billingState: null,
    daysRemaining: null,
  ),
);

MemberStats _stats({
  DateTime? endDate,
  int visits = 7,
  DateTime? lastCheckInAt,
  String code = 'M-0042',
  String? plan = 'Regular',
}) => MemberStats(
  streakDays: 0,
  checkInsThisMonth: visits,
  lastCheckInAt: lastCheckInAt,
  firstName: 'Ana',
  fullName: 'Ana Cruz',
  memberCode: code,
  currentEndDate: endDate,
  planCategory: plan,
);

Future<void> _pump(
  WidgetTester tester, {
  required MemberStats stats,
  bool classesEnabled = false,
  List<Map<String, dynamic>> events = const [],
  bool failEvents = false,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = _FakeApi(events)..failEvents = failEvents;
  final router = GoRouter(
    initialLocation: '/member-home',
    routes: [
      GoRoute(
        path: '/member-home',
        builder: (_, _) => const MemberHomeScreen(),
      ),
      for (final path in const [
        '/me/card',
        '/me/attendance',
        '/me/membership',
        '/member-settings',
        '/member-schedule',
        '/member-community',
      ])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('stub:$path')),
        ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuth(_member(classesEnabled: classesEnabled)),
        ),
        memberStatsProvider.overrideWith((ref) async => stats),
        communityRepositoryProvider.overrideWithValue(CommunityRepository(api)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('real data only', () {
    testWidgets('header, pass card, stats and visits come from the member', (
      tester,
    ) async {
      final end = _today().add(const Duration(days: 30));
      final yesterday = DateTime.now().toUtc().subtract(
        const Duration(days: 1),
      );
      await _pump(
        tester,
        stats: _stats(endDate: end, lastCheckInAt: yesterday),
      );

      expect(find.text('Welcome, Ana'), findsOneWidget);
      // Gym name: the header line and the card's top-left.
      expect(find.text('Iron Works'), findsOneWidget);
      expect(find.text('IRON WORKS'), findsOneWidget);
      expect(find.text('MEMBER PASS'), findsOneWidget);
      expect(find.text('ANA CRUZ'), findsOneWidget);
      expect(find.text('M-0042'), findsOneWidget);
      expect(find.text('VALID THRU'), findsOneWidget);
      expect(find.text(DateFormat('MM/yy').format(end)), findsOneWidget);

      expect(find.text('30'), findsOneWidget);
      expect(find.text('days left'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Valid until ${DateFormat('MMM d, yyyy').format(end)}'),
          findsOneWidget);

      expect(find.text('7'), findsOneWidget);
      expect(find.text('this month'), findsOneWidget);
      expect(find.text('Last visit: Yesterday'), findsOneWidget);
    });

    testWidgets('none of the old placeholder content is left', (tester) async {
      await _pump(
        tester,
        stats: _stats(endDate: _today().add(const Duration(days: 30))),
      );
      for (final fake in [
        'Occupancy',
        'Zarga',
        '223912',
        'VIP',
        'NFC',
        'Deadlift',
        'CHAMPIONSHIP',
        'MOMENTUM',
        'STREAK',
      ]) {
        expect(find.textContaining(fake), findsNothing, reason: fake);
      }
      // The old tile showed a QR that looked scannable but wasn't the
      // member's real, rotating code.
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('a member with no code or plan sees no invented ones', (
      tester,
    ) async {
      await _pump(tester, stats: _stats(code: '', plan: null));
      expect(find.text('MEMBER ID'), findsNothing);
      expect(find.text('NO ACTIVE PLAN'), findsOneWidget); // valid thru slot
      expect(find.text('No active plan'), findsOneWidget); // pass validity
      expect(find.text('No plan'), findsOneWidget); // badge
      expect(find.text('Last visit: None yet'), findsOneWidget);
    });
  });

  group('pass validity badge reuses statusFor', () {
    testWidgets('expiring', (tester) async {
      await _pump(
        tester,
        stats: _stats(endDate: _today().add(const Duration(days: 3))),
      );
      expect(find.text('Expiring'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the last valid day is still active', (tester) async {
      await _pump(tester, stats: _stats(endDate: _today()));
      expect(find.text('Last day'), findsOneWidget);
      expect(find.text('Expiring'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
    });

    testWidgets('expired', (tester) async {
      final end = _today().subtract(const Duration(days: 5));
      await _pump(tester, stats: _stats(endDate: end));
      // Value and badge both say Expired.
      expect(find.text('Expired'), findsNWidgets(2));
      expect(find.text('Ended ${DateFormat('MMM d, yyyy').format(end)}'),
          findsOneWidget);
    });
  });

  group('class booking is gated by the gym setting', () {
    testWidgets('classes off: no Book Class, History still works', (
      tester,
    ) async {
      await _pump(tester, stats: _stats(), classesEnabled: false);
      expect(find.text('Book Class'), findsNothing);
      expect(find.text('History'), findsOneWidget);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('stub:/me/attendance'), findsOneWidget);
    });

    testWidgets('classes on: Book Class opens the schedule', (tester) async {
      await _pump(tester, stats: _stats(), classesEnabled: true);
      expect(find.text('History'), findsOneWidget);
      await tester.tap(find.text('Book Class'));
      await tester.pumpAndSettle();
      expect(find.text('stub:/member-schedule'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('quick entry opens the digital check-in card', (tester) async {
      await _pump(tester, stats: _stats());
      await tester.tap(find.text('Show QR to Check In'));
      await tester.pumpAndSettle();
      expect(find.text('stub:/me/card'), findsOneWidget);
    });

    testWidgets('pass validity opens membership details', (tester) async {
      await _pump(tester, stats: _stats());
      await tester.tap(find.text('PASS VALIDITY'));
      await tester.pumpAndSettle();
      expect(find.text('stub:/me/membership'), findsOneWidget);
    });

    testWidgets('the avatar opens profile and settings', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, stats: _stats());
      await tester.tap(find.bySemanticsLabel('Profile and settings'));
      await tester.pumpAndSettle();
      expect(find.text('stub:/member-settings'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('View All goes to the community feed', (tester) async {
      await _pump(tester, stats: _stats());
      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();
      expect(find.text('stub:/member-community'), findsOneWidget);
    });
  });

  group('upcoming events', () {
    testWidgets('shows the next two real events, soonest first', (
      tester,
    ) async {
      final t = _today();
      await _pump(
        tester,
        stats: _stats(),
        events: [
          _eventJson('past', date: t.subtract(const Duration(days: 2))),
          _eventJson('cancelled',
              date: t.add(const Duration(days: 1)), canceled: true),
          _eventJson('later', date: t.add(const Duration(days: 20))),
          _eventJson('soon', date: t.add(const Duration(days: 2))),
          _eventJson('today', date: t),
        ],
      );
      expect(find.text('today'), findsOneWidget);
      expect(find.text('soon'), findsOneWidget);
      expect(find.text('later'), findsNothing); // only two
      expect(find.text('past'), findsNothing);
      expect(find.text('cancelled'), findsNothing);
      // Same card as the feed: its EVENT tag and like/comment footer.
      expect(find.text('EVENT'), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('today')).dy,
        lessThan(tester.getTopLeft(find.text('soon')).dy),
      );
    });

    testWidgets('nothing upcoming says so instead of inventing an event', (
      tester,
    ) async {
      await _pump(
        tester,
        stats: _stats(),
        events: [
          _eventJson('old', date: _today().subtract(const Duration(days: 9))),
        ],
      );
      expect(find.text('No upcoming events right now.'), findsOneWidget);
      expect(find.text('old'), findsNothing);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      await _pump(tester, stats: _stats(), failEvents: true);
      expect(find.text("Couldn't load events."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('upcomingEvents()', () {
    final today = DateTime(2026, 9, 19);

    test('keeps today, drops past and cancelled, sorts, limits', () {
      final result = upcomingEvents([
        _event('c', date: DateTime(2026, 9, 25)),
        _event('past', date: DateTime(2026, 9, 18)),
        _event('gone', date: DateTime(2026, 9, 20), canceled: true),
        _event('a', date: DateTime(2026, 9, 19)),
        _event('b', date: DateTime(2026, 9, 22)),
      ], today);
      expect(result.map((e) => e.id), ['a', 'b']);
      expect(
        upcomingEvents([_event('c', date: DateTime(2026, 9, 25))], today)
            .single
            .id,
        'c',
      );
    });

    test('same-day events order by start time, no time last', () {
      final d = DateTime(2026, 9, 20);
      final result = upcomingEvents([
        _event('none', date: d),
        _event('late', date: d, startTime: '18:00:00'),
        _event('early', date: d, startTime: '07:30:00'),
      ], today, limit: 3);
      expect(result.map((e) => e.id), ['early', 'late', 'none']);
    });
  });

  group('lastVisitLabel()', () {
    final today = DateTime(2026, 9, 19);
    // 2026-09-19 07:00 Manila == 2026-09-18 23:00 UTC — a check-in the
    // gym calls "today" even though the UTC date is yesterday.
    test('uses the gym\'s calendar day, not UTC', () {
      expect(lastVisitLabel(DateTime.utc(2026, 9, 18, 23), today), 'Today');
    });

    test('yesterday, days ago, and dates', () {
      expect(lastVisitLabel(DateTime.utc(2026, 9, 18, 2), today), 'Yesterday');
      expect(lastVisitLabel(DateTime.utc(2026, 9, 15, 2), today), '4 days ago');
      expect(lastVisitLabel(DateTime.utc(2026, 9, 1, 2), today), 'Sep 1');
      expect(lastVisitLabel(null, today), 'None yet');
    });
  });
}
