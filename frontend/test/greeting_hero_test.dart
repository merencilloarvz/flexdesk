import 'package:flexdesk/features/dashboard/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 360}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('greets in gym time and shows the numbers', (tester) async {
    await tester.pumpWidget(
      _host(
        GreetingHero(
          gymId: 'g',
          gymName: 'Iron Works Cebu',
          // 7:57 PM gym-local
          now: DateTime(2026, 9, 25, 19, 57),
          checkIns: 12,
          members: 340,
          currencyCode: 'PHP',
          showSales: false,
        ),
      ),
    );
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Iron Works Cebu'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('340'), findsOneWidget);
    expect(find.text('Sales today'), findsNothing); // staff: no sales block
  });

  testWidgets('a very long gym name wraps to two lines without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GreetingHero(
          gymId: 'g',
          gymName: 'Zarga Fitness and Wellness Center of Northern Cebu',
          now: DateTime(2026, 9, 25, 9),
          checkIns: 1234567,
          members: 98765,
          currencyCode: 'PHP',
          showSales: false,
        ),
        width: 300,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
