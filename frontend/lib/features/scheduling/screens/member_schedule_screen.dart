import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../shell/app_shell.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_providers.dart';
import 'my_bookings_screen.dart';

// Mirrors BOOKING_HORIZON_DAYS in the server's views.py — if that ever
// changes, this must change with it, or a member can tap a date the
// server will reject.
const _bookingHorizonDays = 14;

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
    }
    setState(() => _actioningSlotId = null);
    // Any outcome re-fetches — the screen's numbers were already stale the
    // moment they rendered; this corrects them in front of the member
    // instead of leaving a wrong count showing.
    await _load();
  }

  Future<void> _cancel(ScheduleSlot slot) async {
    final bookingId = slot.myBookingId;
    if (bookingId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Text('Cancel your booking for ${slot.label}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel booking'),
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
    }
    setState(() => _actioningSlotId = null);
    await _load();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
            child: const Text('My bookings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _dates.length,
                itemBuilder: (context, i) => _DateChip(
                  date: _dates[i],
                  selected: _isSameDay(_dates[i], _selectedDate),
                  onTap: () => _selectDate(_dates[i]),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : (_slots == null || _slots!.isEmpty)
                  ? const Center(
                      child: Text(
                        'No slots run on this day.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          AppShell.reservedNavHeight + 24,
                        ),
                        children: [
                          for (final slot in _slots!)
                            _ScheduleSlotTile(
                              slot: slot,
                              busy: _actioningSlotId == slot.id,
                              onBook: () => _book(slot),
                              onCancel: () => _cancel(slot),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
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
      child: Container(
        width: 56,
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTeal : AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekdays[date.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white70 : AppColors.muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSlotTile extends StatelessWidget {
  const _ScheduleSlotTile({
    required this.slot,
    required this.busy,
    required this.onBook,
    required this.onCancel,
  });

  final ScheduleSlot slot;
  final bool busy;
  final VoidCallback onBook;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final booked = slot.myBookingId != null;
    final full = !booked && slot.spotsLeft <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${slot.startTime.substring(0, 5)}–${slot.endTime.substring(0, 5)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  full
                      ? 'Full'
                      : '${slot.spotsLeft} spot${slot.spotsLeft == 1 ? '' : 's'} left',
                  style: TextStyle(
                    color: full ? AppColors.expiredBg : AppColors.muted,
                    fontSize: 12,
                    fontWeight: full ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            height: 36,
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : booked
                ? OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Booked'),
                  )
                : full
                ? const OutlinedButton(onPressed: null, child: Text('Full'))
                : FilledButton(
                    onPressed: onBook,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentTeal,
                    ),
                    child: const Text('Book'),
                  ),
          ),
        ],
      ),
    );
  }
}
