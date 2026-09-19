import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/server_clock.dart';
import '../../../core/qr/qr_totp.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/me_repository.dart';
import '../providers/me_providers.dart';
import '../providers/qr_card_providers.dart';
import '../widgets/member_pass_style.dart';

/// Phase 3b Part B — the member's digital check-in card (spec B1-B6).
/// Reachable from Home as the card's own most-prominent action.
class DigitalCardScreen extends ConsumerStatefulWidget {
  const DigitalCardScreen({super.key});

  @override
  ConsumerState<DigitalCardScreen> createState() => _DigitalCardScreenState();
}

enum _CardStatus { loading, needsConnection, error, ready }

class _DigitalCardScreenState extends ConsumerState<DigitalCardScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  String? _secretB32;
  int _period = QrTotp.periodSeconds;
  _CardStatus _status = _CardStatus.loading;
  String _errorMessage = '';
  String _code = '';
  int _secondsLeft = 0;

  CachedMeSummary? _summary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _raiseBrightness();
    _loadSummary();
    _loadSecret();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _restoreBrightness();
    super.dispose();
  }

  // Brightness must come back down the moment the card leaves the
  // foreground, not just when the screen is actually popped — otherwise
  // backgrounding the app (home button, a phone call, the app switcher)
  // while the card stays open leaves the screen lit at full brightness
  // for as long as the app sits in the background. The ticker is pure
  // battery cost behind a backgrounded screen with nothing visible to
  // update, so it's paused the same way; resuming recomputes the code
  // immediately, so nothing is lost by not ticking while hidden.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _restoreBrightness();
        _ticker?.cancel();
        _ticker = null;
        break;
      case AppLifecycleState.inactive:
        _restoreBrightness();
        break;
      case AppLifecycleState.resumed:
        if (!mounted) return;
        _raiseBrightness();
        if (_secretB32 != null) _startTicking();
        break;
      default:
        break;
    }
  }

  // B2 — raised while the card is open, restored on dispose (and on
  // backgrounding — see didChangeAppLifecycleState above). Best-effort:
  // some platforms/emulators don't support application-level brightness
  // control, and that must never block the card itself from working.
  Future<void> _raiseBrightness() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {}
  }

  Future<void> _restoreBrightness() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }

  // The card's status chip and days-remaining come from the same cached
  // summary blob MeRepository already keeps for the home screen's
  // offline-cold-start case (B2: "status from the cached summary") —
  // never memberStatsProvider, which has no offline fallback of its own.
  Future<void> _loadSummary() async {
    final cached = await ref.read(meRepositoryProvider).readCachedSummary();
    if (mounted && cached != null) setState(() => _summary = cached);
    try {
      final fresh = await ref.read(meRepositoryProvider).refreshSummary();
      if (mounted) {
        setState(
          () => _summary = CachedMeSummary(
            summary: fresh,
            fetchedAt: DateTime.now(),
          ),
        );
      }
    } catch (_) {
      // Offline or a transient failure — keep whatever cache was read
      // above, if any. The card itself doesn't depend on this succeeding.
    }
  }

  String? _memberId() {
    final authState = ref.read(authControllerProvider);
    return authState is AuthAuthenticated ? authState.user.id : null;
  }

  // B3/B4: only ever fetches when nothing is cached yet. A reset secret
  // is picked up solely through "Refresh card" in Settings clearing the
  // cache first, never by silently re-fetching here.
  Future<void> _loadSecret() async {
    final memberId = _memberId();
    if (memberId == null) return;
    final repo = ref.read(qrCardRepositoryProvider);

    final cached = await repo.readCached(memberId);
    if (cached != null) {
      _secretB32 = cached.secretB32;
      _period = cached.period;
      _startTicking();
      return;
    }

    if (mounted) setState(() => _status = _CardStatus.loading);
    try {
      final fetched = await repo.fetchAndCache(memberId);
      _secretB32 = fetched.secretB32;
      _period = fetched.period;
      _startTicking();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.kind == ApiExceptionKind.network
            ? _CardStatus.needsConnection
            : _CardStatus.error;
        _errorMessage = e.message;
      });
    }
  }

  void _startTicking() {
    _tick();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // Regenerates the code whenever the underlying time step advances —
  // effectively every 60 seconds (A6/B2) — while ticking every second so
  // the countdown ring/label stays live. Always against
  // ServerClock.now(), never the bare device clock: a drifted phone
  // clock must never desync the card from what the desk scanner accepts.
  void _tick() {
    final secret = _secretB32;
    if (secret == null || !mounted) return;
    final now = ref.read(serverClockProvider).now();
    final unixSeconds = now.millisecondsSinceEpoch / 1000;
    final step = QrTotp.timeStep(unixSeconds);
    final secondsIntoStep = unixSeconds.floor() % _period;
    setState(() {
      _status = _CardStatus.ready;
      _code = QrTotp.computeCode(secret, step);
      _secondsLeft = _period - secondsIntoStep;
    });
  }

  String _formattedCode(String code) {
    if (code.length != 8) return code;
    return '${code.substring(0, 4)} ${code.substring(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final memberId = _memberId();
    final summary = _summary?.summary;

    // Visual only: the dark member-pass gradient runs behind the whole
    // screen, app bar included, so the QR tile floats on it.
    return Scaffold(
      backgroundColor: AppColors.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text(
          'Digital card',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: memberPassGradient),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: MemberPassRingsPainter()),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: kToolbarHeight),
                child: memberId == null
                    ? const _CardSpinner()
                    : summary != null && summary.isArchived
                    ? _ArchivedBanner(gymName: summary.gymName)
                    : _buildBody(summary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(MeSummary? summary) {
    switch (_status) {
      case _CardStatus.loading:
        return const _CardSpinner();
      case _CardStatus.needsConnection:
        return _MessageState(
          icon: Icons.wifi_off_rounded,
          message: 'Connect once to set up your card.',
          onRetry: _loadSecret,
        );
      case _CardStatus.error:
        return _MessageState(
          icon: Icons.error_outline,
          message: _errorMessage,
          onRetry: _loadSecret,
        );
      case _CardStatus.ready:
        return _CardContent(
          gymName: summary?.gymName ?? '',
          fullName: summary?.fullName ?? '',
          memberCode: summary?.memberCode ?? '',
          endDate: summary?.currentEndDate,
          code: _formattedCode(_code),
          qrPayload: '${QrTotp.checkinPrefix}|${_memberId()}|$_code',
          secondsLeft: _secondsLeft,
          period: _period,
        );
    }
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.ink,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner({required this.gymName});

  final String gymName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_accounts_outlined,
              size: 48,
              color: Colors.white54,
            ),
            const SizedBox(height: 12),
            Text(
              gymName.isNotEmpty
                  ? 'Your membership at $gymName is no longer active.'
                  : 'Your membership is no longer active.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.gymName,
    required this.fullName,
    required this.memberCode,
    required this.endDate,
    required this.code,
    required this.qrPayload,
    required this.secondsLeft,
    required this.period,
  });

  final String gymName;
  final String fullName;
  final String memberCode;
  final DateTime? endDate;
  final String code;
  final String qrPayload;
  final int secondsLeft;
  final int period;

  @override
  Widget build(BuildContext context) {
    final today = GymTime.today();
    final status = statusFor(endDate, today);
    final days = daysRemaining(endDate, today);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              gymName.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              memberCode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppColors.accentTealBg.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 12),
            _StatusChip(status: status, daysLeft: days),
            const SizedBox(height: 28),
            SizedBox(
              width: 272,
              height: 272,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 272,
                    height: 272,
                    child: CircularProgressIndicator(
                      value: period == 0 ? 0 : secondsLeft / period,
                      strokeWidth: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accentGreen,
                      ),
                    ),
                  ),
                  // The QR stays dark-on-white so it scans reliably; the
                  // white tile floats on the gradient.
                  Container(
                    width: 240,
                    height: 240,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: qrPayload,
                      version: QrVersions.auto,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Refreshes in ${secondsLeft}s',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spinner tinted for the dark card background.
class _CardSpinner extends StatelessWidget {
  const _CardSpinner();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.daysLeft});

  final MembershipStatus status;
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    final (bg, label) = switch (status) {
      MembershipStatus.active => (
        AppColors.activeBg,
        daysLeft != null ? '$daysLeft days left' : 'Active',
      ),
      MembershipStatus.expiring => (
        AppColors.expiringBg,
        daysLeft != null ? '$daysLeft days left' : 'Expiring soon',
      ),
      MembershipStatus.expired => (AppColors.expiredBg, 'Expired'),
      MembershipStatus.noMembership => (AppColors.noMembershipBg, 'No plan'),
    };

    // The fill is still the status color from statusFor(); the light edge
    // and soft shadow keep it (especially the teal "active") from
    // dissolving into the gradient behind it.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
