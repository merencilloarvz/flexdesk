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

/// Thrown by a [QrScannerScreen.onScanned] handler to show [message] as
/// the failure banner and resume the camera (C3) — the shared scanner
/// never has to know whether that message came from a rejected API
/// call (check-in) or a local parsing rule (claim, D2); it just shows
/// whatever text the handler decided on.
class QrScanFailure implements Exception {
  const QrScanFailure(this.message);
  final String message;
}

/// The shared camera engine behind both Phase 3b Part C (staff
/// check-in) and Part D (member claim). Everything scan-type-specific
/// — what a detected payload means, what to do with it, and what to
/// call the screen — lives in [title] and [onScanned]; this widget
/// only owns the camera lifecycle, the C2 single-shot guard, the
/// framing guide, and the failure banner/resume behavior, so neither
/// caller has to reimplement (or risk diverging on) any of that.
///
/// [onScanned] returns the value to pop the screen with on success, or
/// throws [QrScanFailure] to show a message and keep scanning.
class QrScannerScreen<T extends Object> extends ConsumerStatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.title,
    required this.onScanned,
  });

  final String title;
  final Future<T> Function(String payload) onScanned;

  @override
  ConsumerState<QrScannerScreen<T>> createState() => _QrScannerScreenState<T>();
}

class _QrScannerScreenState<T extends Object>
    extends ConsumerState<QrScannerScreen<T>> {
  late final MobileScannerController _controller;
  Timer? _resumeTimer;

  // C2 — mobile_scanner's detect callback fires many times per second
  // for one code held up to the camera. Without this guard, one scan
  // fires several onScanned calls — for check-in specifically, the
  // first verify-qr call consumes the time step and every call after
  // it returns "that code has already been used", a working scan that
  // looks broken. Being synchronous is the whole fix: this is checked
  // and set, and the camera is paused, before this callback's first
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
    // pause(), not stop() — stop() tears the camera session down
    // (black rectangle through verification/the confirmation sheet/any
    // error banner); pause() keeps the preview visible while halting
    // detection. Both route through the same private _stop() helper in
    // the installed mobile_scanner 7.4.1 source, which synchronously
    // cancels the barcode-stream subscription before either method's
    // own single `await` — confirmed from source, not assumed — so
    // pause() closes the guard's race exactly as stop() did.
    // ignore: unawaited_futures
    _controller.pause();

    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) {
      _fail("Couldn't read that code");
      return;
    }
    // ignore: unawaited_futures
    _handle(raw);
  }

  Future<void> _handle(String payload) async {
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.onScanned(payload);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on QrScanFailure catch (e) {
      _fail(e.message);
    }
  }

  // A failure shows the specific message and returns to the camera,
  // never back out to the calling screen (C3). Auto-resumes after a
  // short pause so whoever's holding the phone isn't left staring at a
  // dead camera, but a tap resumes immediately too.
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
    // start() is pause()'s documented counterpart too, not just
    // stop()'s — mobile_scanner's own doc comment on pause() says "the
    // camera can be restarted using start()", and the method-channel
    // implementation resets its internal _pausing flag inside start(),
    // confirming a resumed camera goes through the same call as a
    // fresh one. There is no separate resume() on the controller.
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
        title: Text(widget.title),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          // A framing guide. Purely visual; the scan window is the
          // full camera preview, this never narrows detection.
          const IgnorePointer(child: Center(child: _FrameGuide())),
          if (_verifying)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
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

/// Phase 3b Part C — the staff check-in scanner. Verifies a scanned
/// code via `POST /check-ins/verify-qr/` and pops with the verified
/// [QrVerifyResult] on success; CheckInScreen renders its confirmation
/// sheet directly from that — this screen never creates a check-in
/// itself (C1).
class CheckInQrScannerScreen extends ConsumerWidget {
  const CheckInQrScannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return QrScannerScreen<QrVerifyResult>(
      title: 'Scan membership card',
      onScanned: (payload) async {
        try {
          final data = await ref.read(checkInsApiProvider).verifyQr(payload);
          return QrVerifyResult.fromJson(data);
        } on ApiException catch (e) {
          throw QrScanFailure(e.message);
        }
      },
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
// controller starts; if that's denied, this is what the user sees
// instead, regardless of which scanner (check-in or claim) is open.
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
                    ? 'Camera access is off for FlexDesk. Turn it on in '
                          "your phone's settings to scan a code."
                    : "Couldn't start the camera.",
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
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
