import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_providers.dart';
import 'slot_bookings_screen.dart';
import 'time_slot_edit_screen.dart';

enum _TimeFilter { all, morning, evening }

const _stripeColors = [
  AppColors.accentTeal,
  AppColors.categoryPurple,
  AppColors.expiringBg,
  AppColors.categoryTeal,
];

Color _stripeFor(String label) =>
    _stripeColors[label.hashCode.abs() % _stripeColors.length];

class TimeSlotListScreen extends ConsumerStatefulWidget {
  const TimeSlotListScreen({super.key});

  @override
  ConsumerState<TimeSlotListScreen> createState() => _TimeSlotListScreenState();
}

class _TimeSlotListScreenState extends ConsumerState<TimeSlotListScreen> {
  late DateTime _selectedDate;
  List<TimeSlot>? _slots;
  bool _loading = true;
  String? _error;
  _TimeFilter _filter = _TimeFilter.all;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _dayLetters = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  void initState() {
    super.initState();
    _selectedDate = GymTime.today();
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
          .fetchTimeSlots(date: _selectedDate);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _selectDate(DateTime d) {
    setState(() => _selectedDate = d);
    _load();
  }

  void _changeWeek(int deltaDays) {
    setState(
      () => _selectedDate = _selectedDate.add(Duration(days: deltaDays)),
    );
    _load();
  }

  bool _isToday(DateTime d) {
    final today = GymTime.today();
    return d.year == today.year && d.month == today.month && d.day == today.day;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _openEdit([TimeSlot? slot]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TimeSlotEditScreen(slot: slot)),
    );
    if (changed == true) _load();
  }

  int _startMinutes(TimeSlot s) {
    final parts = s.startTime.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  bool _matchesFilter(TimeSlot s) {
    if (_filter == _TimeFilter.all) return true;
    final startMin = _startMinutes(s);
    return _filter == _TimeFilter.morning ? startMin < 720 : startMin >= 720;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isOwner =
        authState is AuthAuthenticated && authState.user.role == UserRole.owner;

    final slots = _slots ?? const <TimeSlot>[];
    final weekday = _selectedDate.weekday;
    final runningToday =
        slots
            .where(
              (s) =>
                  s.isActive && s.days.contains(weekday) && _matchesFilter(s),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final inactive =
        slots
            .where(
              (s) =>
                  !s.isActive && s.days.contains(weekday) && _matchesFilter(s),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final weekStart = _selectedDate.subtract(
      Duration(days: _selectedDate.weekday - 1),
    );
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'Schedule',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton(
              onPressed: () => _openEdit(),
              backgroundColor: AppColors.accentTeal,
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_months[_selectedDate.month - 1]} ${_selectedDate.year}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          size: 20,
                          color: AppColors.accentTeal,
                        ),
                        onPressed: () => _changeWeek(-7),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.accentTeal,
                        ),
                        onPressed: () => _changeWeek(7),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final d in weekDays)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectDate(d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _isSameDay(d, _selectedDate)
                                  ? AppColors.accentTeal
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _isSameDay(d, _selectedDate)
                                      ? 'TODAY'
                                      : _dayLetters[d.weekday - 1],
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: _isSameDay(d, _selectedDate)
                                        ? Colors.white70
                                        : AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${d.day}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _isSameDay(d, _selectedDate)
                                        ? Colors.white
                                        : (_isToday(d)
                                              ? AppColors.accentTeal
                                              : AppColors.ink),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.fieldBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _FilterTab(
                        label: 'All Slots (${runningToday.length})',
                        selected: _filter == _TimeFilter.all,
                        onTap: () => setState(() => _filter = _TimeFilter.all),
                      ),
                    ),
                    Expanded(
                      child: _FilterTab(
                        label: 'Morning',
                        selected: _filter == _TimeFilter.morning,
                        onTap: () =>
                            setState(() => _filter = _TimeFilter.morning),
                      ),
                    ),
                    Expanded(
                      child: _FilterTab(
                        label: 'Evening',
                        selected: _filter == _TimeFilter.evening,
                        onTap: () =>
                            setState(() => _filter = _TimeFilter.evening),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : slots.isEmpty
                  ? _EmptyState(isOwner: isOwner, onCreate: () => _openEdit())
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentTeal,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                        children: [
                          if (runningToday.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  isOwner
                                      ? 'No more slots scheduled for today.\nTap + New Slot to publish an open facility hour.'
                                      : 'No slots run on this day.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          for (final slot in runningToday)
                            _SlotCard(
                              slot: slot,
                              isOwner: isOwner,
                              dimmed: false,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SlotBookingsScreen(
                                    slot: slot,
                                    date: _selectedDate,
                                  ),
                                ),
                              ),
                              onEdit: isOwner ? () => _openEdit(slot) : null,
                            ),
                          if (inactive.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'INACTIVE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final slot in inactive)
                              _SlotCard(
                                slot: slot,
                                isOwner: isOwner,
                                dimmed: true,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SlotBookingsScreen(
                                      slot: slot,
                                      date: _selectedDate,
                                    ),
                                  ),
                                ),
                                onEdit: isOwner ? () => _openEdit(slot) : null,
                              ),
                          ],
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

class _FilterTab extends StatelessWidget {
  const _FilterTab({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentTeal : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.isOwner,
    required this.dimmed,
    required this.onTap,
    required this.onEdit,
  });

  final TimeSlot slot;
  final bool isOwner;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  int _durationMinutes() {
    int toMin(String t) {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    return toMin(slot.endTime) - toMin(slot.startTime);
  }

  String _durationLabel() {
    final diff = _durationMinutes();
    if (diff < 60) return '$diff mins';
    final hrs = diff ~/ 60;
    final mins = diff % 60;
    return mins == 0 ? '$hrs hr${hrs == 1 ? '' : 's'}' : '$hrs hr $mins mins';
  }

  @override
  Widget build(BuildContext context) {
    final full = slot.bookedCount != null && slot.bookedCount! >= slot.capacity;
    final booked = slot.bookedCount ?? 0;
    final fillPct = slot.capacity > 0
        ? (booked / slot.capacity).clamp(0.0, 1.0)
        : 0.0;
    final stripe = _stripeFor(slot.label);

    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: stripe),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${slot.startTime.substring(0, 5)} – ${slot.endTime.substring(0, 5)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: stripe,
                                  ),
                                ),
                              ),
                              Text(
                                _durationLabel(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              if (full) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'FULL',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.errorText,
                                    ),
                                  ),
                                ),
                              ],
                              if (isOwner && onEdit != null) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: onEdit,
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                      color: AppColors.subtle,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            slot.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          if (slot.coachName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 13,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Coach ${slot.coachName}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Capacity',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '$booked/${slot.capacity} booked',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: full
                                                ? AppColors.errorText
                                                : AppColors.ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: fillPct,
                                        minHeight: 5,
                                        backgroundColor: AppColors.fieldBg,
                                        valueColor: AlwaysStoppedAnimation(
                                          full ? AppColors.errorText : stripe,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isOwner) ...[
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: onTap,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.ink,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: const Text(
                                    'Manage Slot',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isOwner, required this.onCreate});
  final bool isOwner;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentTeal,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.event_available,
                size: 28,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Slots are the classes or sessions members can book — like '
              '"Morning CrossFit" or "6 AM Spin". Set the days, time, and '
              'how many people can join.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (isOwner) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Create your first slot'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
