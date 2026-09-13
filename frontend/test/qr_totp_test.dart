// Phase 3b spec A2.1 / B5 — cross-implementation test vectors, hard-coded
// exactly as given in the spec and in core/tests/test_qr.py. Do not
// regenerate these from QrTotp itself: a test that checks an
// implementation against itself proves nothing about whether the Dart
// and Python sides actually agree.
import 'package:flutter_test/flutter_test.dart';

import 'package:flexdesk/core/qr/qr_totp.dart';

// Adjust the `package:flexdesk/...` import above if your pubspec's
// `name:` isn't `flexdesk` — same note as db_smoke_test.dart.

void main() {
  group('QrTotp — A2.1 vectors', () {
    test('vector 1', () {
      const secret =
          'AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPQ====';
      final step = QrTotp.timeStep(1767225600);
      expect(step, 29453760);
      expect(QrTotp.computeCode(secret, step), '42081074');
    });

    test('vector 2 has a leading zero', () {
      // Catches an integer-vs-string formatting bug: '09458587' as an
      // int would silently lose the leading zero and fail this
      // assertion.
      const secret =
          'IFAUCQKBIFAUCQKBIFAUCQKBIFAUCQKBIFAUCQKBIFAUCQKBIFAQ====';
      final step = QrTotp.timeStep(1767225660);
      expect(step, 29453761);
      final code = QrTotp.computeCode(secret, step);
      expect(code, '09458587');
      expect(code.length, 8);
    });

    test('vector 3', () {
      const secret =
          '777777777777777777777777777777777777777777777777777Q====';
      final step = QrTotp.timeStep(1767312000);
      expect(step, 29455200);
      expect(QrTotp.computeCode(secret, step), '99002962');
    });
  });
}
