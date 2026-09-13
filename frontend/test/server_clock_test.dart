// Phase 3b spec A6 — the server clock offset. Covers ServerClock's own
// parsing/persistence rules directly, plus AuthInterceptor.onResponse's
// "call handler.next(response) exactly once, on every path" guarantee —
// same rule the existing onError follows.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flexdesk/core/api/auth_interceptor.dart';
import 'package:flexdesk/core/api/server_clock.dart';
import 'package:flexdesk/core/api/token_storage.dart';

// Adjust the `package:flexdesk/...` imports above if your pubspec's
// `name:` isn't `flexdesk` — same note as db_smoke_test.dart.

Response<Object?> _fakeResponse({Map<String, List<String>>? headers}) {
  return Response(
    requestOptions: RequestOptions(path: '/members/'),
    statusCode: 200,
    headers: Headers.fromMap(headers ?? {}),
  );
}

void main() {
  group('ServerClock', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('a valid Date header sets the offset', () async {
      final clock = ServerClock();
      await clock.ready;

      final serverTime = DateTime.now().toUtc().add(const Duration(minutes: 5));
      await clock.updateFromDateHeader(HttpDate.format(serverTime));

      // HttpDate has one-second resolution, plus a little real execution
      // time between computing serverTime and the offset being derived —
      // a few seconds of slack keeps this from being flaky without
      // hiding a real bug (a correct offset is within a couple seconds
      // of 5 minutes, not off by minutes).
      expect(clock.offset.inSeconds, inInclusiveRange(295, 305));
    });

    test('a missing header leaves the offset unchanged', () async {
      final clock = ServerClock();
      await clock.ready;

      await clock.updateFromDateHeader(null);

      expect(clock.offset, Duration.zero);
    });

    test('a malformed header leaves the offset unchanged, without throwing', () async {
      final clock = ServerClock();
      await clock.ready;

      await expectLater(
        clock.updateFromDateHeader('definitely not an HTTP date'),
        completes,
      );

      expect(clock.offset, Duration.zero);
    });

    test('the persisted value is read back on a fresh instance', () async {
      final first = ServerClock();
      await first.ready;

      final serverTime = DateTime.now().toUtc().add(const Duration(minutes: 10));
      await first.updateFromDateHeader(HttpDate.format(serverTime));
      expect(first.offset.inSeconds, inInclusiveRange(595, 605));

      // A fresh instance — the cold-start case — sharing the same
      // (mocked) on-disk store.
      final second = ServerClock();
      await second.ready;

      expect(second.offset.inSeconds, first.offset.inSeconds);
    });

    test(
      'two responses one second apart both update now() but write '
      'through only once',
      () async {
        final clock = ServerClock();
        await clock.ready;

        final firstServerTime = DateTime.now().toUtc().add(
          const Duration(minutes: 2),
        );
        await clock.updateFromDateHeader(HttpDate.format(firstServerTime));
        final firstOffset = clock.offset;

        final secondServerTime = firstServerTime.add(const Duration(seconds: 1));
        await clock.updateFromDateHeader(HttpDate.format(secondServerTime));
        final secondOffset = clock.offset;

        // Both calls moved the in-memory value — now() genuinely
        // reflects each new reading, even though the second one falls
        // under the write-through threshold.
        expect(secondOffset, isNot(equals(firstOffset)));
        expect(
          (secondOffset - firstOffset).inMilliseconds,
          inInclusiveRange(500, 1500),
        );

        // Only the first write actually reached disk: a second,
        // independent instance hydrating from the same (mocked) store
        // must read back the FIRST offset, not the second — proving
        // the second update's ~1-second difference never wrote through.
        final fresh = ServerClock();
        await fresh.ready;
        expect(fresh.offset.inMilliseconds, firstOffset.inMilliseconds);
      },
    );
  });

  group('AuthInterceptor.onResponse', () {
    late ServerClock serverClock;
    late AuthInterceptor interceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      serverClock = ServerClock();
      interceptor = AuthInterceptor(
        tokenStorage: TokenStorage(),
        baseUrl: 'https://example.test',
        onSessionExpired: () {},
        serverClock: serverClock,
      );
    });

    test(
      'a valid Date header updates the offset and still passes the '
      'response through exactly once',
      () async {
        await serverClock.ready;
        final serverTime = DateTime.now().toUtc().add(
          const Duration(minutes: 3),
        );
        final response = _fakeResponse(
          headers: {
            'date': [HttpDate.format(serverTime)],
          },
        );
        final handler = ResponseInterceptorHandler();

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.isCompleted, isTrue);
        expect(serverClock.offset.inSeconds, inInclusiveRange(175, 185));
      },
    );

    test(
      'a missing Date header leaves the offset unchanged and still '
      'passes the response through exactly once',
      () async {
        await serverClock.ready;
        final response = _fakeResponse();
        final handler = ResponseInterceptorHandler();

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.isCompleted, isTrue);
        expect(serverClock.offset, Duration.zero);
      },
    );

    test(
      'a malformed Date header leaves the offset unchanged, does not '
      'throw, and still passes the response through exactly once',
      () async {
        await serverClock.ready;
        final response = _fakeResponse(
          headers: {
            'date': ['not-a-real-date'],
          },
        );
        final handler = ResponseInterceptorHandler();

        expect(() => interceptor.onResponse(response, handler), returnsNormally);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(handler.isCompleted, isTrue);
        expect(serverClock.offset, Duration.zero);
      },
    );

    test(
      'calling handler.next again after onResponse throws — proving it '
      'was already completed exactly once, not left pending',
      () async {
        await serverClock.ready;
        final response = _fakeResponse();
        final handler = ResponseInterceptorHandler();

        interceptor.onResponse(response, handler);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          () => handler.next(response),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
