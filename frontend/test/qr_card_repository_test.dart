// Phase 3b B4 — "Refresh card" must fetch before it clears: a failed or
// throttled fetch must never leave a member with no secret at all. See
// QrCardRepository.refreshSecret and its doc comment.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flexdesk/core/api/qr_secret_storage.dart';
import 'package:flexdesk/features/members_home/data/me_api.dart';
import 'package:flexdesk/features/members_home/data/qr_card_repository.dart';

// Adjust the `package:flexdesk/...` imports above if your pubspec's
// `name:` isn't `flexdesk` — same note as db_smoke_test.dart.

/// Same pattern as _ThrowingCheckInsApi in offline_queue_park_test.dart —
/// a real API call is never made; the constructed Dio() is just to
/// satisfy the superclass constructor.
class _FakeMeApi extends MeApi {
  _FakeMeApi({this.result, this.exception}) : super(Dio());

  final Map<String, dynamic>? result;
  final ApiException? exception;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> fetchQrSecret() async {
    callCount++;
    final exception = this.exception;
    if (exception != null) throw exception;
    return result!;
  }
}

/// In-memory stand-in for QrSecretStorage — the real class wraps
/// flutter_secure_storage's platform channel, which isn't available in
/// a plain `flutter_test` unit test. Every public method is overridden,
/// so the unused FlutterSecureStorage the superclass constructor sets
/// up is never touched.
class _FakeQrSecretStorage extends QrSecretStorage {
  final _store = <String, String>{};

  @override
  Future<String?> read(String memberId) async => _store[memberId];

  @override
  Future<void> write(String memberId, String secret) async {
    _store[memberId] = secret;
  }

  @override
  Future<void> clear(String memberId) async {
    _store.remove(memberId);
  }
}

void main() {
  const memberId = 'member-1';

  group('QrCardRepository.refreshSecret', () {
    test(
      'a failing fetch leaves the previously cached secret readable',
      () async {
        final storage = _FakeQrSecretStorage();
        await storage.write(memberId, 'OLDSECRETVALUE');

        final api = _FakeMeApi(
          exception: ApiException(
            kind: ApiExceptionKind.throttled,
            message: 'Too many attempts. Try again shortly.',
          ),
        );
        final repo = QrCardRepository(api, storage);

        await expectLater(
          repo.refreshSecret(memberId),
          throwsA(isA<ApiException>()),
        );

        final cached = await repo.readCached(memberId);
        expect(cached, isNotNull);
        expect(cached!.secretB32, 'OLDSECRETVALUE');
      },
    );

    test('a successful fetch replaces the cached secret', () async {
      final storage = _FakeQrSecretStorage();
      await storage.write(memberId, 'OLDSECRETVALUE');

      final api = _FakeMeApi(
        result: {'secret': 'NEWSECRETVALUE', 'period': 60, 'digits': 8},
      );
      final repo = QrCardRepository(api, storage);

      final result = await repo.refreshSecret(memberId);
      expect(result.secretB32, 'NEWSECRETVALUE');

      final cached = await repo.readCached(memberId);
      expect(cached!.secretB32, 'NEWSECRETVALUE');
    });
  });
}
