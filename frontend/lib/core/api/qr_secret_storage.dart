import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where a member's QR secret lives on-device (Phase 3b spec B3).
///
/// Secure storage, never Drift (unencrypted) and never SharedPreferences
/// — the secret is a live credential, unlike the clock offset in
/// ServerClock. Keyed by member id (`qr_secret_<member_uuid>`) so two
/// accounts signed into the same device across a logout/login cycle can
/// never read each other's secret.
class QrSecretStorage {
  QrSecretStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'flexdesk.qr_secret.';

  String _keyFor(String memberId) => '$_keyPrefix$memberId';

  Future<String?> read(String memberId) async {
    try {
      return await _storage.read(key: _keyFor(memberId));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String memberId, String secret) async {
    await _storage.write(key: _keyFor(memberId), value: secret);
  }

  /// B4's "Refresh card" action, and part of logout — clears only this
  /// member's entry, never the whole secure-storage namespace.
  Future<void> clear(String memberId) async {
    try {
      await _storage.delete(key: _keyFor(memberId));
    } catch (_) {}
  }
}

final qrSecretStorageProvider = Provider<QrSecretStorage>(
  (ref) => QrSecretStorage(),
);
