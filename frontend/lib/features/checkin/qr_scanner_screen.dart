import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api/api_exception.dart';
import '../members/providers/check_ins_provider.dart';

/// The server's authoritative answer from `verify-qr` — computed
/// against the gym's timezone from current data at the moment of
/// verification. CheckInScreen renders its confirmation sheet from
/// this directly rather than re-deriving membership_status/days-
/// remaining/already-checked-in-today from the local Drift cache,
/// which may be stale or may not have this member at all.
class QrVerifyResult {
  const QrVerifyResult({
    required this.memberId,
    required this.fullName,
    required this.memberCode,
    required this.membershipStatus,
    required this.currentEndDate,
    required this.daysRemaining,
    required this.alreadyCheckedInToday,
  });

  final String memberId;
  final String fullName;
  final String memberCode;

  /// One of 'active' / 'expiring' / 'expired' / 'no_membership' —
  /// exactly the strings `Member.with_status()` annotates on the
  /// backend, and exactly what CheckInsRepository.createMemberCheckIn
  /// expects. Passed straight through; never re-derived locally.
  final String membershipStatus;
  final DateTime? currentEndDate;
  final int? daysRemaining;
  final bool alreadyCheckedInToday;

  factory QrVerifyResult.fromJson(Map<String, dynamic> json) {
    return QrVerifyResult(
      memberId: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      memberCode: json['member_code'] as String? ?? '',
      membershipStatus: json['membership_status'] as String? ?? 'no_membership',
      currentEndDate: json['current_end_date'] != null
          ? DateTime.parse(json['current_end_date'] as String)
          : null,
      daysRemaining: json['days_remaining'] as int?,
      alreadyCheckedInToday: json['already_checked_in_today'] as bool? ?? false,
    );
  }
}

/// Phase 3b Part C — the staff scanner. Verifies a scanned check-in QR
/// via `POST /check-ins/verify-qr/` and pops with the verified
/// [QrVerifyResult] on success; CheckInScreen renders its confirmation
/// sheet directly from that — this screen never creates a check-in
/// itself (C1).
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  late final MobileScannerController _controller;
  Timer? _resumeTimer;

  // C2 — mobile_scanner's detect callback fires many times per second
  // for one code held up to the camera. Without this guard the first
  // verify-qr call consumes the time step and every call after it
  // returns "that code has already been used" — a working scan that
  // looks broken. Being synchronous is the whole fix: this is checked
  // and set, and the camera is stopped, before this callback's first
  // `await` — never after one.
  bool _handled = false;

  bool _verifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    _handled = true;
    // ignore: unawaited_futures
    _controller.stop();

    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) {
      _fail("Couldn't read that code");
      return;
    }
    // ignore: unawaited_futures
    _verify(raw);
  }

  Future<void> _verify(String payload) async {
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });
    try {
      final data = await ref.read(checkInsApiProvider).verifyQr(payload);
      if (!mounted) return;
      Navigator.of(context).pop(QrVerifyResult.fromJson(data));
    } on ApiException catch (e) {
      _fail(e.message);
    }
  }

  // C3 — a failure shows the specific A9 message and returns to the
  // camera, never back out to the check-in screen. Auto-resumes after
  // a short pause so staff aren't left staring at a dead camera, but a
  // tap resumes immediately too.
  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _errorMessage = message;
    });
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 2, milliseconds: 500), () {
      if (mounted) _resumeScanning();
    });
  }

  void _resumeScanning() {
    _resumeTimer?.cancel();
    setState(() {
      _errorMessage = null;
      _handled = false;
    });
    // ignore: unawaited_futures
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Scan membership card'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          // C1 — a framing guide. Purely visual; the scan window is the
          // full camera preview, this never narrows detection.
          const IgnorePointer(child: Center(child: _FrameGuide())),
          if (_verifying)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          if (_errorMessage != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 40,
              child: _ErrorBanner(
                message: _errorMessage!,
                onTap: _resumeScanning,
              ),
            ),
        ],
      ),
    );
  }
}

class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Camera permission denial (or any other camera error) must never be a
// blank screen — same failure shape as the INTERNET permission bug
// (spec 0.2). mobile_scanner requests CAMERA at runtime the moment the
// controller starts; if that's denied, this is what staff see instead.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                permissionDenied
                    ? 'Camera access is off for FlexDesk. Turn it on in your '
                          "phone's settings to scan a membership card."
                    : "Couldn't start the camera. Search for the member "
                          'instead.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text('Search instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
