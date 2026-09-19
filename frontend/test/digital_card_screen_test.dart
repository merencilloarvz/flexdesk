import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flexdesk/core/api/server_clock.dart';
import 'package:flexdesk/core/qr/qr_totp.dart';
import 'package:flexdesk/core/theme/colors.dart';
import 'package:flexdesk/core/utils/gym_time.dart';
import 'package:flexdesk/features/auth/providers/auth_providers.dart';
import 'package:flexdesk/features/members_home/data/me_repository.dart';
import 'package:flexdesk/features/members_home/data/qr_card_repository.dart';
import 'package:flexdesk/features/members_home/providers/me_providers.dart';
import 'package:flexdesk/features/members_home/providers/qr_card_providers.dart';
import 'package:flexdesk/features/members_home/screens/digital_card_screen.dart';
import 'package:flexdesk/features/members_home/widgets/member_pass_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

// A fixed instant 20s into a 60s step, so the ring reads 40/60.
final _now = DateTime.utc(2026, 9, 19, 10, 0, 20);
const _secret = 'JBSWY3DPEHPK3PXP';

class _FixedClock implements ServerClock {
  @override
  DateTime now() => _now;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQrRepo implements QrCardRepository {
  _FakeQrRepo({this.cached = true, this.fetchError});
  final bool cached;
  final ApiException? fetchError;

  @override
  Future<QrCardSecret?> readCached(String memberId) async => cached
      ? const QrCardSecret(
          secretB32: _secret,
          period: QrTotp.periodSeconds,
          digits: QrTotp.digits,
        )
      : null;

  @override
  Future<QrCardSecret> fetchAndCache(String memberId) async =>
      throw fetchError!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMeRepo implements MeRepository {
  _FakeMeRepo(this.summary);
  final MeSummary summary;

  @override
  Future<CachedMeSummary?> readCachedSummary() async =>
      CachedMeSummary(summary: summary, fetchedAt: _now);

  @override
  Future<MeSummary> refreshSummary() async => summary;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    AuthUser(
      id: 'member-1',
      email: 'ana@example.com',
      fullName: 'Ana Cruz',
      defaultLocationId: null,
      role: UserRole.unknown,
      accountType: 'member',
      gym: null,
      mustChangePassword: false,
    ),
  );
}

MeSummary _summary({DateTime? end, bool archived = false}) => MeSummary(
  id: 'member-1',
  fullName: 'Ana Cruz',
  memberCode: 'M-0042',
  currentEndDate: end,
  currentPlanCategory: 'Regular',
  isArchived: archived,
  gymName: 'Iron Works',
  gymTimezone: 'Asia/Manila',
  gymCurrency: 'PHP',
  checkInsThisMonth: 0,
  lastCheckInAt: null,
);

Future<void> _pump(
  WidgetTester tester, {
  MeSummary? summary,
  _FakeQrRepo? qr,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuth.new),
        serverClockProvider.overrideWithValue(_FixedClock()),
        qrCardRepositoryProvider.overrideWithValue(qr ?? _FakeQrRepo()),
        meRepositoryProvider.overrideWithValue(
          _FakeMeRepo(
            summary ??
                _summary(end: GymTime.today().add(const Duration(days: 30))),
          ),
        ),
      ],
      child: const MaterialApp(home: DigitalCardScreen()),
    ),
  );
  // Not pumpAndSettle: the once-a-second ticker never settles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Tears the screen down so its periodic ticker is cancelled (dispose).
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Color? _textColor(WidgetTester t, String text) =>
    t.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('sits on the dark member-pass gradient, not plain white', (
    tester,
  ) async {
    await _pump(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.ink);
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    final gradientBox = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((b) => (b.decoration as BoxDecoration).gradient != null);
    expect(gradientBox, isNotEmpty);
    expect(
      (gradientBox.first.decoration as BoxDecoration).gradient,
      memberPassGradient,
    );
    await _unmount(tester);
  });

  testWidgets('text is light against the dark background', (tester) async {
    await _pump(tester);

    expect(_textColor(tester, 'Ana Cruz'), Colors.white);
    expect(find.text('IRON WORKS'), findsOneWidget);
    expect(_textColor(tester, 'IRON WORKS')!.a, greaterThan(0.6));
    // The 8-digit refresh code, and the countdown label.
    final code = QrTotp.computeCode(_secret, QrTotp.timeStep(
      _now.millisecondsSinceEpoch / 1000,
    ));
    final shown = '${code.substring(0, 4)} ${code.substring(4)}';
    expect(_textColor(tester, shown), Colors.white);
    expect(find.text('Refreshes in 40s'), findsOneWidget);
    expect(_textColor(tester, 'Refreshes in 40s')!.a, greaterThan(0.6));

    // The title and back arrow are light on the transparent app bar.
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, Colors.transparent);
    expect(bar.foregroundColor, Colors.white);
    await _unmount(tester);
  });

  testWidgets('the QR stays dark-on-white so it scans', (tester) async {
    await _pump(tester);

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    // Default modules are black; nothing lightened them.
    expect(qr.eyeStyle.color, const Color(0xFF000000));
    expect(qr.dataModuleStyle.color, const Color(0xFF000000));
    expect(qr.backgroundColor, Colors.transparent);

    // ...on a white tile that floats (shadow) rather than the screen going
    // white.
    final tile = tester.widget<Container>(
      find.ancestor(
        of: find.byType(QrImageView),
        matching: find.byType(Container),
      ).first,
    );
    final deco = tile.decoration as BoxDecoration;
    expect(deco.color, Colors.white);
    expect(deco.boxShadow, isNotEmpty);
    expect(deco.borderRadius, isNotNull);
    await _unmount(tester);
  });

  testWidgets('the rotation logic is unchanged: code and ring', (
    tester,
  ) async {
    await _pump(tester);

    final code = QrTotp.computeCode(
      _secret,
      QrTotp.timeStep(_now.millisecondsSinceEpoch / 1000),
    );
    // QrImageView keeps its payload private, so the code the card shows
    // (from the same TOTP step) stands in for it here.
    expect(
      find.text('${code.substring(0, 4)} ${code.substring(4)}'),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsOneWidget);

    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(40 / 60, 0.001));
    // Bright green on the dark gradient, over a faint white track.
    expect(ring.valueColor!.value,
        AppColors.accentGreen);
    expect(ring.backgroundColor!.a, lessThan(0.3));
    await _unmount(tester);
  });

  group('status pill keeps its colors from statusFor()', () {
    testWidgets('active', (tester) async {
      await _pump(tester);
      final pill = _pillFor(tester, '30 days left');
      expect(pill.color, AppColors.activeBg);
      await _unmount(tester);
    });

    testWidgets('expiring', (tester) async {
      await _pump(
        tester,
        summary: _summary(end: GymTime.today().add(const Duration(days: 3))),
      );
      expect(_pillFor(tester, '3 days left').color, AppColors.expiringBg);
      await _unmount(tester);
    });

    testWidgets('expired', (tester) async {
      await _pump(
        tester,
        summary: _summary(end: GymTime.today().subtract(const Duration(days: 4))),
      );
      expect(_pillFor(tester, 'Expired').color, AppColors.expiredBg);
      await _unmount(tester);
    });

    testWidgets('and is edged so it reads on the dark background', (
      tester,
    ) async {
      await _pump(tester);
      final pill = _pillFor(tester, '30 days left');
      expect(pill.border, isNotNull);
      expect(pill.boxShadow, isNotEmpty);
      await _unmount(tester);
    });
  });

  group('the other states are recolored, not changed', () {
    testWidgets('no active membership (archived)', (tester) async {
      await _pump(tester, summary: _summary(archived: true));
      final msg = 'Your membership at Iron Works is no longer active.';
      expect(find.text(msg), findsOneWidget);
      expect(_textColor(tester, msg), Colors.white70);
      expect(find.byType(QrImageView), findsNothing);
      await _unmount(tester);
    });

    testWidgets('needs a connection: message and Retry are legible', (
      tester,
    ) async {
      await _pump(
        tester,
        qr: _FakeQrRepo(
          cached: false,
          fetchError: ApiException(
            kind: ApiExceptionKind.network,
            message: 'offline',
          ),
        ),
      );
      expect(find.text('Connect once to set up your card.'), findsOneWidget);
      expect(_textColor(tester, 'Connect once to set up your card.'),
          Colors.white70);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      await _unmount(tester);
    });
  });
}

BoxDecoration _pillFor(WidgetTester t, String label) {
  final container = t.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return container.decoration as BoxDecoration;
}
