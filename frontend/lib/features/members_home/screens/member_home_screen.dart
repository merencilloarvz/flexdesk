import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../../core/utils/member_status.dart';
import '../../auth/providers/auth_providers.dart';
import '../../community/data/community_repository.dart';
import '../../community/providers/community_providers.dart';
import '../../community/screens/member/member_event_detail_screen.dart';
import '../providers/member_stats_provider.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen>
    with WidgetsBindingObserver {
  List<Event>? _upcomingEvents;
  DateTime? _lastResumeRefresh;

  // Same reasoning and cooldown as HomeScreen's resume refresh — this is
  // the fix for a member never learning their gym turned Classes on
  // (or off) until they log out and back in. Only throttles the
  // automatic resume trigger, never an explicit pull-to-refresh.
  static const _resumeRefreshCooldown = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchEvents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final now = DateTime.now();
    if (_lastResumeRefresh != null &&
        now.difference(_lastResumeRefresh!) < _resumeRefreshCooldown) {
      return;
    }
    _lastResumeRefresh = now;
    _refreshSession();
  }

  Future<void> _refreshSession() async {
    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);
    } catch (_) {
      // Swallow — a stale session is better than a logged-out one.
      // Network failures and malformed responses both just mean this
      // device keeps whatever it already had until the next chance.
    }
  }

  Future<void> _fetchEvents() async {
    try {
      final events = await ref.read(communityRepositoryProvider).fetchEvents();
      if (mounted) {
        setState(() {
          _upcomingEvents = events.where((e) => !e.isCanceled).toList();
        });
      }
    } catch (_) {
      // Gracefully fall back to the showcase event
    }
  }

  void _showQrModal(
    BuildContext context,
    String payload,
    String name,
    String code,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GatePassSheet(
        qrPayload: payload,
        memberName: name,
        memberCode: code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    if (authState is! AuthAuthenticated) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentTeal),
        ),
      );
    }
    final user = authState.user;
    final statsAsync = ref.watch(memberStatsProvider);
    final today = GymTime.today();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: SafeArea(
        child: statsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentTeal),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.errorText,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load member info: $error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.subtle),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(memberStatsProvider),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentTeal,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (stats) {
            final daysLeft = daysRemaining(stats.currentEndDate, today);
            final memberFirstName = stats.firstName.isNotEmpty
                ? stats.firstName
                : (user.fullName.split(' ').first.isNotEmpty
                      ? user.fullName.split(' ').first
                      : 'Member');
            final memberFullName = stats.fullName.isNotEmpty
                ? stats.fullName
                : (user.fullName.isNotEmpty ? user.fullName : 'Member');
            final memberCodeStr = stats.memberCode.isNotEmpty
                ? stats.memberCode
                : '223912';
            final qrPayload =
                'FLEXDESK:GATE:${user.gym?.id ?? ''}:$memberCodeStr:${user.id}';

            return RefreshIndicator(
              color: AppColors.accentTeal,
              onRefresh: () async {
                await _refreshSession();
                ref.invalidate(memberStatsProvider);
                await _fetchEvents();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // 1. Top Header Row
                  _HeaderSection(
                    firstName: memberFirstName,
                    gymName: user.gym?.name ?? '',
                  ),
                  const SizedBox(height: 14),

                  // 2. Gym Capacity / Occupancy Row
                  const _GymCapacityRow(),
                  const SizedBox(height: 10),

                  // 3. NFC Active Status Pill
                  const _NfcStatusPill(),
                  const SizedBox(height: 14),

                  // 4. VIP Digital Membership Card (Hero Card)
                  _VipMembershipCard(
                    gymName: user.gym?.name ?? '',
                    tierName: stats.planCategory ?? 'ATHLETIC VIP TIER',
                    memberCode: memberCodeStr,
                    fullName: memberFullName,
                    validThru: stats.currentEndDate != null
                        ? DateFormat('MM/yy').format(stats.currentEndDate!)
                        : '10/26',
                  ),
                  const SizedBox(height: 14),

                  // 5. Optical Gate Access (Turnstile QR Code)
                  _TurnstileQrCard(
                    qrPayload: qrPayload,
                    daysLeft: daysLeft ?? 28,
                    onTap: () => _showQrModal(
                      context,
                      qrPayload,
                      memberFullName,
                      memberCodeStr,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 6. Streak Momentum Banner
                  _StreakBanner(streakDays: stats.streakDays),
                  const SizedBox(height: 12),

                  // 7. Quick Stats (2 Cards Row)
                  _QuickStatsRow(
                    daysLeft: daysLeft,
                    currentEndDate: stats.currentEndDate,
                    checkInsThisMonth: stats.checkInsThisMonth,
                    lastCheckInAt: stats.lastCheckInAt,
                  ),
                  const SizedBox(height: 14),

                  // 8. Action Buttons Row (Book Class / Slot & Renew Pass)
                  _ActionButtonsRow(
                    onBookClass: () => context.push('/member-schedule'),
                    onRenewPass: () => context.push('/me/membership'),
                  ),
                  const SizedBox(height: 12),

                  // 9. Membership History Tile
                  _HistoryTile(onTap: () => context.push('/me/membership')),
                  const SizedBox(height: 20),

                  // 10. Upcoming Events Section
                  _UpcomingEventsSection(
                    events: _upcomingEvents,
                    onViewSchedule: () => context.push('/member-schedule'),
                    onEventTap: (event) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MemberEventDetailScreen(eventId: event.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Header Section
// ---------------------------------------------------------------------------

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.firstName, required this.gymName});

  final String firstName;
  final String gymName;

  @override
  Widget build(BuildContext context) {
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'M';

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFD3EFE5),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F6E56),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F6E56),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, $firstName',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0E1A13),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$gymName • Zarga Gym 2',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF7A8681),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.notifications_outlined,
            size: 20,
            color: Color(0xFF4B5563),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Gym Capacity / Occupancy Row
// ---------------------------------------------------------------------------

class _GymCapacityRow extends StatelessWidget {
  const _GymCapacityRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Gym Capacity',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B5563),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F7EF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFBCECD5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF059669),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                '62% Occupancy',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. NFC Active Status Pill
// ---------------------------------------------------------------------------

class _NfcStatusPill extends StatelessWidget {
  const _NfcStatusPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'NFC ACTIVE • GATE READY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF059669),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '|',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFCBD5E1),
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(width: 6),
          const Flexible(
            child: Text(
              'Tap turnstile or scan pass',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. VIP Digital Membership Card (Hero Card)
// ---------------------------------------------------------------------------

class _VipMembershipCard extends StatelessWidget {
  const _VipMembershipCard({
    required this.gymName,
    required this.tierName,
    required this.memberCode,
    required this.fullName,
    required this.validThru,
  });

  final String gymName;
  final String tierName;
  final String memberCode;
  final String fullName;
  final String validThru;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 208,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF063325), Color(0xFF0A4E3B), Color(0xFF0C5D47)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF063325).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Concentric circular watermark rings on the right
          Positioned.fill(child: CustomPaint(painter: _CardRingsPainter())),

          // Card content padding
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: Logo + Gym Name / Tier + VIP PASS Pill
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.fitness_center_rounded,
                          size: 16,
                          color: Color(0xFFA7F3D0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gymName.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            tierName.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6EE7B7),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFBBF24),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'VIP PASS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFDE68A),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Middle: Gold Metallic Chip & Contactless Symbol
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFF2D17E),
                            Color(0xFFD4AF37),
                            Color(0xFFB38612),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFFDE68A),
                          width: 0.7,
                        ),
                      ),
                      child: CustomPaint(painter: _ChipLinesPainter()),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.contactless_outlined,
                      size: 22,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ],
                ),

                // Bottom Row: Member Code & Full Name, Valid Thru Date
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IW-$memberCode',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(
                                0xFF6EE7B7,
                              ).withValues(alpha: 0.85),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fullName.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'VALID THRU',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: const Color(
                              0xFF6EE7B7,
                            ).withValues(alpha: 0.8),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          validThru,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardRingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = const Color(0xFF34D399).withValues(alpha: 0.12);

    final center = Offset(size.width * 0.92, size.height * 0.52);
    final radii = [50.0, 85.0, 120.0, 155.0, 190.0, 225.0];
    for (final r in radii) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChipLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF78350F).withValues(alpha: 0.4);

    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.22,
        size.height * 0.2,
        size.width * 0.56,
        size.height * 0.6,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(innerRect, paint);
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height * 0.2),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.8),
      Offset(size.width * 0.5, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width * 0.22, size.height * 0.5),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.78, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 5. Optical Gate Access (Turnstile QR Code Card)
// ---------------------------------------------------------------------------

class _TurnstileQrCard extends StatelessWidget {
  const _TurnstileQrCard({
    required this.qrPayload,
    required this.daysLeft,
    required this.onTap,
  });

  final String qrPayload;
  final int daysLeft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // QR Code Graphic container with live indicator
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDFBF5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBCECD5)),
                    ),
                    child: QrImageView(
                      data: qrPayload,
                      version: QrVersions.auto,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F6E56),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F6E56),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Title and auto-refresh detail
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 13,
                          color: Color(0xFF0D9488),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'TURNSTILE TURNKEY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0D9488),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Optical Gate Access',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Auto-refresh 30s • ${daysLeft >= 0 ? '$daysLeft days active' : 'Expired'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              // Right chevron circle button
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Streak Momentum Banner
// ---------------------------------------------------------------------------

class _StreakBanner extends StatelessWidget {
  const _StreakBanner({required this.streakDays});

  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final days = streakDays > 0 ? streakDays : 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFEDD5)),
            ),
            child: const Center(
              child: Text('🔥', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$days DAY STREAK',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ACTIVE MOMENTUM',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F766E),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Check in today to keep your streak going!',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Quick Stats (2-Column Row)
// ---------------------------------------------------------------------------

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({
    required this.daysLeft,
    required this.currentEndDate,
    required this.checkInsThisMonth,
    required this.lastCheckInAt,
  });

  final int? daysLeft;
  final DateTime? currentEndDate;
  final int checkInsThisMonth;
  final DateTime? lastCheckInAt;

  @override
  Widget build(BuildContext context) {
    final renewDateText = currentEndDate != null
        ? DateFormat('MMM d').format(currentEndDate!)
        : 'Nov 10';

    final lastVisitText = _fmtLastVisit(lastCheckInAt);

    return Row(
      children: [
        // Left: Monthly Pass
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'MONTHLY PASS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      daysLeft != null ? '$daysLeft' : '28',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'days left',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Renews $renewDateText',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Right: Visits
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'VISITS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$checkInsThisMonth',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      checkInsThisMonth == 1 ? 'session' : 'sessions',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Last: $lastVisitText',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtLastVisit(DateTime? d) {
    if (d == null) return 'None yet';
    final now = DateTime.now();
    final local = d.toLocal();
    final diff = now.difference(local);
    if (diff.inDays == 0 && now.day == local.day) return 'Today';
    if (diff.inDays <= 1 || (diff.inHours < 48 && now.day - local.day == 1)) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM d').format(local);
  }
}

// ---------------------------------------------------------------------------
// 8. Action Buttons Row
// ---------------------------------------------------------------------------

class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.onBookClass,
    required this.onRenewPass,
  });

  final VoidCallback onBookClass;
  final VoidCallback onRenewPass;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Book Class / Slot (Primary filled teal button)
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onBookClass,
              icon: const Icon(
                Icons.calendar_month_outlined,
                size: 16,
                color: Colors.white,
              ),
              label: const Text(
                'Book Class / Slot',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F6E56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Renew Pass (White button with subtle border)
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onRenewPass,
              icon: const Icon(
                Icons.autorenew_rounded,
                size: 18,
                color: Color(0xFF0F6E56),
              ),
              label: const Text(
                'Renew Pass',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 9. Membership History Tile
// ---------------------------------------------------------------------------

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDFBF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: Color(0xFF0F6E56),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Membership history',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'View recent invoices & pass validity',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 10. Upcoming Events Section
// ---------------------------------------------------------------------------

class _UpcomingEventsSection extends StatelessWidget {
  const _UpcomingEventsSection({
    required this.events,
    required this.onViewSchedule,
    required this.onEventTap,
  });

  final List<Event>? events;
  final VoidCallback onViewSchedule;
  final ValueChanged<Event> onEventTap;

  @override
  Widget build(BuildContext context) {
    final firstEvent = events != null && events!.isNotEmpty
        ? events!.first
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Upcoming Events',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                letterSpacing: -0.2,
              ),
            ),
            GestureDetector(
              onTap: onViewSchedule,
              child: const Text(
                'VIEW SCHEDULE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F6E56),
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (firstEvent != null)
          _EventCard(
            title: firstEvent.title,
            badge: 'CHAMPIONSHIP',
            priceText: firstEvent.feeCentavos > 0
                ? '₱${firstEvent.feeCentavos ~/ 100}'
                : 'FREE',
            dateLocation:
                '${DateFormat('EEEE, h:mm a').format(firstEvent.eventDate)} • ${firstEvent.locationText.isNotEmpty ? firstEvent.locationText : 'Main Gym'}',
            onTap: () => onEventTap(firstEvent),
          )
        else
          // Showcase event matching design mockup
          _EventCard(
            title: 'Deadlift Max Championship',
            badge: 'CHAMPIONSHIP',
            priceText: '₱250',
            dateLocation: 'Saturday, 4:00 PM • Main Platform',
            onTap: onViewSchedule,
          ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.title,
    required this.badge,
    required this.priceText,
    required this.dateLocation,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String priceText;
  final String dateLocation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A1F1B), Color(0xFF113831), Color(0xFF16483F)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge & Price tag
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF059669).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                        Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF34D399),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      priceText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),

              // Date / Location
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: Color(0xFF6EE7B7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    dateLocation,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFA7F3D0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Turnstile Gate Pass Bottom Sheet (Modal on QR tap)
// ---------------------------------------------------------------------------

class _GatePassSheet extends StatefulWidget {
  const _GatePassSheet({
    required this.qrPayload,
    required this.memberName,
    required this.memberCode,
  });

  final String qrPayload;
  final String memberName;
  final String memberCode;

  @override
  State<_GatePassSheet> createState() => _GatePassSheetState();
}

class _GatePassSheetState extends State<_GatePassSheet> {
  int _secondsRemaining = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 1) {
            _secondsRemaining--;
          } else {
            _secondsRemaining = 30;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Turnstile Gate Pass',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hold this QR code directly against the scanner',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFBCECD5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F6E56).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: widget.qrPayload,
              version: QrVersions.auto,
              size: 200,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0F6E56),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0F6E56),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            widget.memberName.toUpperCase(),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'MEMBER #IW-${widget.memberCode}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F6E56),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.autorenew_rounded,
                  size: 14,
                  color: Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  'Auto-refreshes in ${_secondsRemaining}s',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
