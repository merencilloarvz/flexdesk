import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/gym_time.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_providers.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  bool _showHistory = false;
  List<MyBooking> _bookings = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  final Set<String> _cancelling = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final result = await ref
          .read(scheduleRepositoryProvider)
          .fetchMyBookings(upcoming: !_showHistory, page: 1);
      if (!mounted) return;
      setState(() {
        _bookings = result.bookings;
        _hasMore = result.hasMore;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await ref
          .read(scheduleRepositoryProvider)
          .fetchMyBookings(upcoming: !_showHistory, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _bookings = [..._bookings, ...result.bookings];
        _hasMore = result.hasMore;
        _page += 1;
        _loadingMore = false;
      });
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _cancel(MyBooking booking) async {
    setState(() => _cancelling.add(booking.id));
    final result = await ref
        .read(scheduleRepositoryProvider)
        .cancel(booking.id);
    if (!mounted) return;
    if (result.outcome != BookingActionOutcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? "Couldn't cancel that booking."),
        ),
      );
    }
    setState(() => _cancelling.remove(booking.id));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final today = GymTime.today();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('My Bookings')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Upcoming')),
                  ButtonSegment(value: true, label: Text('History')),
                ],
                selected: {_showHistory},
                onSelectionChanged: (selection) {
                  setState(() => _showHistory = selection.first);
                  _reload();
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _bookings.isEmpty
                  ? Center(
                      child: Text(
                        _showHistory
                            ? 'No past bookings.'
                            : 'No upcoming bookings.',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.pixels >=
                            n.metrics.maxScrollExtent - 200) {
                          _loadMore();
                        }
                        return false;
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        children: [
                          for (final booking in _bookings)
                            _BookingTile(
                              booking: booking,
                              canCancel:
                                  booking.canceledAt == null &&
                                  !booking.date.isBefore(today),
                              busy: _cancelling.contains(booking.id),
                              onCancel: () => _cancel(booking),
                            ),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
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

class _BookingTile extends StatelessWidget {
  const _BookingTile({
    required this.booking,
    required this.canCancel,
    required this.busy,
    required this.onCancel,
  });

  final MyBooking booking;
  final bool canCancel;
  final bool busy;
  final VoidCallback onCancel;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final canceled = booking.canceledAt != null;
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
                  booking.timeSlotLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: canceled ? AppColors.muted : AppColors.ink,
                    decoration: canceled
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_months[booking.date.month - 1]} ${booking.date.day}, ${booking.date.year}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (canCancel)
            busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
