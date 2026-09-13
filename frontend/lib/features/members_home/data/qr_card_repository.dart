import '../../../core/api/qr_secret_storage.dart';
import '../../../core/qr/qr_totp.dart';
import 'me_api.dart';

class QrCardSecret {
  const QrCardSecret({
    required this.secretB32,
    required this.period,
    required this.digits,
  });

  final String secretB32;
  final int period;
  final int digits;
}

/// Orchestrates the member card's secret: secure storage first, the
/// throttled `/me/qr-secret/` endpoint only when nothing is cached yet
/// (Phase 3b B3/B4). Never re-fetches just because the app relaunched —
/// that's what B4 means by "fetches only when the cached secret is
/// absent": a reset on the server is picked up only through the
/// explicit "Refresh card" action clearing the cache first.
class QrCardRepository {
  QrCardRepository(this._api, this._storage);

  final MeApi _api;
  final QrSecretStorage _storage;

  Future<QrCardSecret?> readCached(String memberId) async {
    final secret = await _storage.read(memberId);
    if (secret == null || secret.isEmpty) return null;
    return QrCardSecret(
      secretB32: secret,
      period: QrTotp.periodSeconds,
      digits: QrTotp.digits,
    );
  }

  /// Fetches from the server and caches the result. Throws ApiException
  /// on failure — the caller (the card screen) decides how to render a
  /// network failure versus any other kind (B6).
  ///
  /// The write only happens after the fetch succeeds, which is exactly
  /// what makes [refreshSecret] below safe to reuse: a failed or
  /// throttled fetch never touches whatever secret is already cached.
  Future<QrCardSecret> fetchAndCache(String memberId) async {
    final json = await _api.fetchQrSecret();
    final secret = json['secret'] as String;
    await _storage.write(memberId, secret);
    return QrCardSecret(
      secretB32: secret,
      period: json['period'] as int? ?? QrTotp.periodSeconds,
      digits: json['digits'] as int? ?? QrTotp.digits,
    );
  }

  /// B4's "Refresh card" action. Fetches first and only overwrites the
  /// cached secret once that succeeds — never deletes the old secret
  /// up front. A member whose fetch fails or is throttled (10/hour)
  /// keeps whatever secret they already had, working, rather than
  /// being left with none at all until a later attempt succeeds.
  /// Failure is rethrown for the caller to surface.
  Future<QrCardSecret> refreshSecret(String memberId) =>
      fetchAndCache(memberId);
}
