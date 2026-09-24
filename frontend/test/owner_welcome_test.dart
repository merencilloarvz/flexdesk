import 'package:flexdesk/core/router/app_router.dart';
import 'package:flexdesk/features/auth/providers/auth_providers.dart';
import 'package:flexdesk/features/auth/screens/owner_welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AuthState _user({
  String role = 'owner',
  String accountType = 'staff',
  bool seen = false,
  bool needsSetup = true,
  bool blocked = false,
}) {
  return AuthAuthenticated(
    AuthUser.fromJson({
      'id': 'u1',
      'email': 'o@example.com',
      'full_name': 'Maria Santos',
      'role': role,
      'account_type': accountType,
      'must_change_password': false,
      'has_seen_owner_welcome': seen,
      'gym': {
        'id': 'g1',
        'name': 'Trial Gym',
        'needs_setup': needsSetup,
        'subscription_status': 'trialing',
        'subscription_blocked': blocked,
        'trial_ends_at': DateTime.now()
            .add(const Duration(days: 14))
            .toIso8601String(),
        'billing_state': blocked ? 'trial_expired' : 'trial_active',
        'days_remaining': blocked ? 0 : 14,
      },
    }),
  );
}

void main() {
  group('welcome routing', () {
    test('new owner is sent to /welcome, not /setup', () {
      expect(appRedirect(_user(), '/signup'), '/welcome');
      expect(appRedirect(_user(), '/home'), '/welcome');
      expect(appRedirect(_user(), '/welcome'), isNull);
    });

    test('owner who has seen it goes home and is never forced to /setup', () {
      final s = _user(seen: true);
      expect(appRedirect(s, '/welcome'), '/home');
      expect(appRedirect(s, '/signup'), '/home');
      expect(appRedirect(s, '/home'), isNull);
      expect(appRedirect(s, '/setup'), '/home');
    });

    test('pricing screen route is not blocked when reached from Settings', () {
      expect(appRedirect(_user(seen: true), '/plans/manage'), isNull);
    });

    test('staff never see the welcome flow', () {
      final s = _user(role: 'staff');
      expect(appRedirect(s, '/home'), isNull);
    });

    test('members never see the welcome flow', () {
      final s = _user(role: 'member', accountType: 'member');
      expect(appRedirect(s, '/welcome'), '/member-home');
    });

    test('lapsed trial still reaches /subscribe after the welcome', () {
      expect(appRedirect(_user(seen: true, blocked: true), '/home'),
          '/subscribe');
    });
  });

  group('OwnerWelcomeScreen', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuth.new),
          ],
          child: const MaterialApp(home: OwnerWelcomeScreen()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('slide 1 greets by first name with the 14 day badge',
        (tester) async {
      await pump(tester);
      expect(find.text('Welcome, Maria!'), findsOneWidget);
      expect(find.text('14 days free'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('swiping reaches slides 2 and 3, Skip stays visible',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('A quick tour'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Membership plans'), findsOneWidget);
      expect(find.text('Store items'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });
  });
}

class _FakeAuth extends AuthController {
  @override
  AuthState build() => _user();
}
