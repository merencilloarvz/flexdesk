import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Dart mirror of `backend/core/qr.py`. Normative — every constant and
/// step here is pinned by Phase 3b spec section A2, and the two
/// implementations must never diverge. Agreement is proven by the
/// shared A2.1 test vectors (see test/qr_totp_test.dart and
/// core/tests/test_qr.py), never by inspection.
class QrTotp {
  QrTotp._();

  static const periodSeconds = 60;
  static const digits = 8;

  // QR payload prefixes (A8). CLAIM_PREFIX is only ever handled by Part
  // D (claim QR, not built yet) — it's here as a shared constant so a
  // future implementation can't invent a different string.
  static const checkinPrefix = 'FDCHK1';
  static const claimPrefix = 'FDCLAIM1';

  static int timeStep(double unixSeconds) =>
      (unixSeconds / periodSeconds).floor();

  /// [secretB32] is the base32-encoded secret exactly as returned by
  /// `/me/qr-secret/`. Decoded back to the raw 32 bytes for the HMAC
  /// key — NOT the base32 text itself (A2.2), the single most likely
  /// place this could disagree with the Python side.
  static String computeCode(String secretB32, int step) {
    final key = _base32Decode(secretB32);
    final message = ByteData(8)..setInt64(0, step, Endian.big);
    final digest =
        Hmac(sha256, key).convert(message.buffer.asUint8List()).bytes;

    final offset = digest[31] & 0x0F;
    final binary =
        ((digest[offset] & 0x7F) << 24) |
        (digest[offset + 1] << 16) |
        (digest[offset + 2] << 8) |
        digest[offset + 3];
    final code = binary % 100000000; // 10^digits
    return code.toString().padLeft(digits, '0');
  }

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// RFC 4648 base32 decode. Padding (`=`) is stripped rather than
  /// validated — the server always sends a fully-padded string, and
  /// stripping is sufficient to recover the original bytes either way.
  static Uint8List _base32Decode(String input) {
    final cleaned = input.toUpperCase().replaceAll('=', '');
    final bytes = <int>[];
    var buffer = 0;
    var bitsLeft = 0;
    for (final rune in cleaned.runes) {
      final value = _alphabet.indexOf(String.fromCharCode(rune));
      if (value == -1) {
        throw FormatException('Invalid base32 character in secret');
      }
      buffer = (buffer << 5) | value;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return Uint8List.fromList(bytes);
  }
}
