import 'package:flutter/material.dart';

import '../../../core/qr/qr_totp.dart';
import '../../checkin/qr_scanner_screen.dart';

/// Phase 3b Part D2 — the claim screen's Scan button opens this, which
/// reuses the exact same camera engine as the staff check-in scanner
/// (QrScannerScreen — same C2 guard, same pause/resume, same framing
/// guide and permission handling), configured for the claim payload
/// instead. Nothing here calls the server: a claim QR's code is read
/// entirely client-side and handed back to fill in the claim form —
/// verification only happens once the member submits email + code + a
/// new password.
class ClaimQrScannerScreen extends StatelessWidget {
  const ClaimQrScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return QrScannerScreen<String>(
      title: 'Scan claim code',
      onScanned: (payload) async {
        final parts = payload.split('|');

        // A9 in reverse (D2): a check-in card scanned here gets the
        // specific complementary message, not a generic "couldn't
        // read" — staff hear the mirror image of this at the desk
        // when a claim card is scanned there.
        if (parts.isNotEmpty && parts[0] == QrTotp.checkinPrefix) {
          throw const QrScanFailure(
            "That's a membership card, not an account setup code",
          );
        }

        if (parts.length != 2 || parts[0] != QrTotp.claimPrefix) {
          throw const QrScanFailure("Couldn't read that code");
        }

        return parts[1];
      },
    );
  }
}
