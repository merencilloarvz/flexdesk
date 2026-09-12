import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../../shell/app_shell.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_providers.dart';
import 'my_bookings_screen.dart';

// Booking horizon mirrors server configuration
const _bookingHorizonDays = 14;

enum _ClassCategory {
  all('All Classes'),
  strength('Powerlifting & Strength'),
  hiit('HIIT & Conditioning'),
  mobility('Mobility & Core');

  const _ClassCategory(this.label);
  final String label;
}

class MemberScheduleScreen extends ConsumerStatefulWidget {
  const MemberScheduleScreen({super.key});

  @override
  ConsumerState<MemberScheduleScreen> createState() =>
      _MemberScheduleScreenState();
}

class _MemberScheduleScreenState extends ConsumerState<MemberScheduleScreen> {
  late DateTime _selectedDate;
  late final List<DateTime> _dates;
  List<ScheduleSlot>? _slots;
  bool _loading = true;
  String? _error;
  String? _actioningSlotId;
  _ClassCategory _selectedCategory = _ClassCategory.all;
  int _myBookingsCount = 0;

  @override
  void initState() {
    super.initState();
    final today = GymTime.today();
    _dates = List.generate(
      _bookingHorizonDays,
      (i) => today.add(Duration(days: i)),
    );
    _selectedDate = _dates.first;
    _load();
    _loadBookingsCount();
  }

  Future<void> _loadBookingsCount() async {
    try {
      final res = await ref
          .read(scheduleRepositoryProvider)
          .fetchMyBookings(upcoming: true);
      if (mounted) {
        setState(() {
          _myBookingsCount = res.bookings
              .where((b) => b.canceledAt == null)
              .length;
        });
      }
    } catch (_) {
      // Non-critical count indicator
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slots = await ref
          .read(scheduleRepositoryProvider)
          .fetchSchedule(_selectedDate);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.kind == ApiExceptionKind.network
            ? 'You need an internet connection to see the schedule.'
            : e.message;
        _loading = false;
      });
    }
  }

  void _selectDate(DateTime d) {
    setState(() => _selectedDate = d);
    _load();
  }

  Future<void> _book(ScheduleSlot slot) async {
    setState(() => _actioningSlotId = slot.id);
    final result = await ref
        .read(scheduleRepositoryProvider)
        .book(slot.id, _selectedDate);
    if (!mounted) return;
    if (result.outcome != BookingActionOutcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? "Couldn't book that slot.")),
      );
    } else {
      _loadBookingsCount();
    }
    setState(() => _actioningSlotId = null);
    await _load();
  }

  Future<void> _cancel(ScheduleSlot slot) async {
    final bookingId = slot.myBookingId;
    if (bookingId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cancel Booking?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text('Do you want to cancel your booking for ${slot.label}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Keep Booking',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actioningSlotId = slot.id);
    final result = await ref.read(scheduleRepositoryProvider).cancel(bookingId);
    if (!mounted) return;
    if (result.outcome != BookingActionOutcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? "Couldn't cancel that booking."),
        ),
      );
    } else {
      _loadBookingsCount();
    }
    setState(() => _actioningSlotId = null);
    await _load();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<ScheduleSlot> _filterSlots(List<ScheduleSlot> all) {
    if (_selectedCategory == _ClassCategory.all) return all;
    return all.where((slot) {
      final name = slot.label.toLowerCase();
      return switch (_selectedCategory) {
        _ClassCategory.all => true,
        _ClassCategory.strength =>
          name.contains('strength') ||
              name.contains('barbell') ||
              name.contains('deadlift') ||
              name.contains('power') ||
              name.contains('weight'),
        _ClassCategory.hiit =>
          name.contains('hiit') ||
              name.contains('metcon') ||
              name.contains('conditioning') ||
              name.contains('turf') ||
              name.contains('cardio') ||
              name.contains('interval'),
        _ClassCategory.mobility =>
          name.contains('mobility') ||
              name.contains('core') ||
              name.contains('yoga') ||
              name.contains('pilates') ||
              name.contains('stretch'),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final gymName = authState is AuthAuthenticated
        ? authState.user.gym?.name ?? 'Iron Works Cebu'
        : 'Iron Works Cebu';

    final filteredSlots = _slots != null
        ? _filterSlots(_slots!)
        : <ScheduleSlot>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${gymName.toUpperCase()} • MEMBER SCHEDULE',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F6E56),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Schedule',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0E1A13),
                          letterSpacing: -0.5,
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const MyBookingsScreen(),
                                ),
                              )
                              .then((_) => _loadBookingsCount()),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'My bookings',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F6E56),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD3EFE5),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$_myBookingsCount',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F6E56),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. Date Carousel (Horizontal Strip)
            SizedBox(
              height: 84,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _dates.length,
                itemBuilder: (context, i) {
                  final d = _dates[i];
                  final isSelected = _isSameDay(d, _selectedDate);
                  return _DateCard(
                    date: d,
                    selected: isSelected,
                    onTap: () => _selectDate(d),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // 3. Category Filter Chips Row
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final cat in _ClassCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: cat.label,
                        selected: _selectedCategory == cat,
                        onTap: () => setState(() => _selectedCategory = cat),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 4. Subheader Info Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${DateFormat('EEEE, MMM d').format(_selectedDate)} • ${filteredSlots.length} Session${filteredSlots.length == 1 ? '' : 's'} Available',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(
                        Icons.tune_rounded,
                        size: 14,
                        color: Color(0xFF0F6E56),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Filter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F6E56),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 5. Slot List Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentTeal,
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.wifi_off_rounded,
                              size: 44,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF4B5563)),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _load,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F6E56),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filteredSlots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 40,
                            color: Color(0xFF9CA3AF),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No classes scheduled for this filter.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF0F6E56),
                      onRefresh: () async {
                        await _load();
                        await _loadBookingsCount();
                      },
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          AppShell.reservedNavHeight + 28,
                        ),
                        itemCount: filteredSlots.length,
                        itemBuilder: (context, i) {
                          final slot = filteredSlots[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _ClassSessionCard(
                              slot: slot,
                              busy: _actioningSlotId == slot.id,
                              onBook: () => _book(slot),
                              onCancel: () => _cancel(slot),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date Card Chip
// ---------------------------------------------------------------------------

class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 68,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF0D4B39) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0D4B39)
                    : const Color(0xFFE5E7EB),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? const Color(0xFF0D4B39).withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.02),
                  blurRadius: selected ? 8 : 4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _weekdays[date.weekday - 1],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.75)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : const Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0D4B39)
                  : (date.weekday % 2 == 0
                        ? const Color(0xFF10B981)
                        : Colors.transparent),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category Filter Chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D4B39) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF0D4B39) : const Color(0xFFE5E7EB),
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: const Color(0xFF0D4B39).withValues(alpha: 0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF4B5563),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Class Session Card (Available & Booked States)
// ---------------------------------------------------------------------------

class _ClassSessionCard extends StatelessWidget {
  const _ClassSessionCard({
    required this.slot,
    required this.busy,
    required this.onBook,
    required this.onCancel,
  });

  final ScheduleSlot slot;
  final bool busy;
  final VoidCallback onBook;
  final VoidCallback onCancel;

  String _fmtTime(String t) {
    try {
      final parts = t.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final h12 = hour % 12 == 0 ? 12 : hour % 12;
      final hPad = h12.toString().padLeft(2, '0');
      return '$hPad:$minute $period';
    } catch (_) {
      return t.length >= 5 ? t.substring(0, 5) : t;
    }
  }

  int _calcDuration(String start, String end) {
    try {
      final sp = start.split(':');
      final ep = end.split(':');
      final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final diff = em - sm;
      return diff > 0 ? diff : 60;
    } catch (_) {
      return 60;
    }
  }

  String _deriveCategory(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('strength') ||
        lower.contains('barbell') ||
        lower.contains('deadlift') ||
        lower.contains('power')) {
      return 'STRENGTH';
    }
    if (lower.contains('hiit') ||
        lower.contains('metcon') ||
        lower.contains('conditioning') ||
        lower.contains('turf')) {
      return 'HIIT';
    }
    if (lower.contains('mobility') ||
        lower.contains('core') ||
        lower.contains('yoga')) {
      return 'MOBILITY';
    }
    return 'CLASS';
  }

  String _deriveLocation(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('strength') || lower.contains('deadlift')) {
      return 'Level 2 • Powerlifting Rig Area';
    }
    if (lower.contains('metcon') ||
        lower.contains('turf') ||
        lower.contains('hiit')) {
      return 'Level 1 • Athletic Turf Zone';
    }
    return 'Main Studio Area';
  }

  String _deriveCoach(String coachName, String label) {
    if (coachName.isNotEmpty) return coachName;
    final lower = label.toLowerCase();
    if (lower.contains('strength') || lower.contains('deadlift')) {
      return 'Coach Marcus (USAW Level 2)';
    }
    if (lower.contains('metcon') ||
        lower.contains('turf') ||
        lower.contains('hiit')) {
      return 'Coach Elena V.';
    }
    return 'Coach Alex P.';
  }

  @override
  Widget build(BuildContext context) {
    final booked = slot.myBookingId != null;
    final full = !booked && slot.spotsLeft <= 0;
    final duration = _calcDuration(slot.startTime, slot.endTime);
    final category = _deriveCategory(slot.label);
    final location = _deriveLocation(slot.label);
    final coach = _deriveCoach(slot.coachName, slot.label);
    final fillPct = slot.capacity > 0
        ? (slot.bookedCount / slot.capacity).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: booked ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
          width: booked ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: booked
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // If booked, top accent highlight bar
          if (booked)
            Container(
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Category + Duration & Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDFBF5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F6E56),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• $duration min',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    if (booked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: Color(0xFF059669),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'BOOKED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (full)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '• Full',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      )
                    else if (slot.spotsLeft <= 3)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '• ${slot.spotsLeft} spots left',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '• ${slot.spotsLeft} spots left',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Class Title
                Text(
                  slot.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0E1A13),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),

                // Metadata Rows
                _MetaRow(
                  icon: Icons.access_time_rounded,
                  text:
                      '${_fmtTime(slot.startTime)} – ${_fmtTime(slot.endTime)}',
                  isBold: true,
                ),
                const SizedBox(height: 4),
                _MetaRow(icon: Icons.location_on_outlined, text: location),
                const SizedBox(height: 4),
                _MetaRow(icon: Icons.person_outline_rounded, text: coach),
                const SizedBox(height: 14),

                // Capacity Filled Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Capacity filled',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${slot.bookedCount} / ${slot.capacity} spots',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fillPct,
                    minHeight: 5,
                    color: const Color(0xFF0F6E56),
                    backgroundColor: const Color(0xFFE5E7EB),
                  ),
                ),
                const SizedBox(height: 16),

                // Booked Confirmed Spot Banner (if booked)
                if (booked) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDFBF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBCECD5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 15,
                              color: Color(0xFF0F6E56),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'You have a confirmed spot',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F6E56),
                              ),
                            ),
                          ],
                        ),
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
                            'PASS ACTIVE',
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
                  ),
                  const SizedBox(height: 12),
                ],

                // Action Button (Book Slot or Manage / Cancel)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: busy
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF0F6E56),
                            ),
                          ),
                        )
                      : booked
                      ? OutlinedButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(
                            Icons.edit_calendar_outlined,
                            size: 15,
                            color: Color(0xFF4B5563),
                          ),
                          label: const Text(
                            'Manage / Cancel Booking',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF9FAFB),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        )
                      : full
                      ? OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF3F4F6),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Session Full',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        )
                      : FilledButton(
                          onPressed: onBook,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0D4B39),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text(
                                'Book Slot',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ],
                          ),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text, this.isBold = false});

  final IconData icon;
  final String text;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF0F6E56)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isBold ? const Color(0xFF1F2937) : const Color(0xFF4B5563),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
