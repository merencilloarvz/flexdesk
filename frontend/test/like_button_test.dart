import 'dart:async';

import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flexdesk/features/community/data/community_repository.dart';
import 'package:flexdesk/features/community/widgets/like_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(LikeButton button) =>
    MaterialApp(home: Scaffold(body: Center(child: button)));

bool _filled(WidgetTester t) =>
    t.widget<Icon>(find.byType(Icon)).icon == Icons.favorite;

void main() {
  testWidgets('flips immediately, then settles on the server state', (
    tester,
  ) async {
    final response = Completer<LikeState>();
    LikeState? reported;
    await tester.pumpWidget(
      _host(
        LikeButton(
          likeCount: 2,
          likedByMe: false,
          onToggle: () => response.future,
          onChanged: (s) => reported = s,
        ),
      ),
    );
    expect(_filled(tester), isFalse);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    // Request still in flight — already flipped.
    expect(_filled(tester), isTrue);
    expect(find.text('3'), findsOneWidget);

    // Someone else liked it too meanwhile: the server's number wins.
    response.complete(const LikeState(likeCount: 5, likedByMe: true));
    await tester.pump();
    expect(_filled(tester), isTrue);
    expect(find.text('5'), findsOneWidget);
    expect(reported?.likeCount, 5);
    expect(reported?.likedByMe, isTrue);
  });

  testWidgets('unliking flips immediately too', (tester) async {
    final response = Completer<LikeState>();
    await tester.pumpWidget(
      _host(
        LikeButton(
          likeCount: 1,
          likedByMe: true,
          onToggle: () => response.future,
        ),
      ),
    );
    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    expect(_filled(tester), isFalse);
    expect(find.text('0'), findsOneWidget);
    response.complete(const LikeState(likeCount: 0, likedByMe: false));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a failed toggle snaps back and says so', (tester) async {
    var reported = false;
    await tester.pumpWidget(
      _host(
        LikeButton(
          likeCount: 2,
          likedByMe: false,
          onToggle: () async => throw ApiException(
            kind: ApiExceptionKind.network,
            message: 'No connection.',
          ),
          onChanged: (_) => reported = true,
        ),
      ),
    );
    await tester.tap(find.byType(LikeButton));
    await tester.pump(); // optimistic frame
    await tester.pump(); // failure handled
    expect(_filled(tester), isFalse);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('No connection.'), findsOneWidget);
    expect(reported, isFalse);
  });

  testWidgets('taps while a request is in flight are ignored', (tester) async {
    var calls = 0;
    final response = Completer<LikeState>();
    await tester.pumpWidget(
      _host(
        LikeButton(
          likeCount: 0,
          likedByMe: false,
          onToggle: () {
            calls++;
            return response.future;
          },
        ),
      ),
    );
    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('1'), findsOneWidget);
    response.complete(const LikeState(likeCount: 1, likedByMe: true));
    await tester.pump();
  });

  testWidgets('adopts new values from the parent when idle', (tester) async {
    Widget build(int count, bool liked) => _host(
      LikeButton(
        likeCount: count,
        likedByMe: liked,
        onToggle: () async => const LikeState(likeCount: 0, likedByMe: false),
      ),
    );
    await tester.pumpWidget(build(1, false));
    await tester.pumpWidget(build(4, true));
    expect(_filled(tester), isTrue);
    expect(find.text('4'), findsOneWidget);
  });
}
