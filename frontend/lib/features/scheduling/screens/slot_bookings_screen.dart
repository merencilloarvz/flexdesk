import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_providers.dart';

class SlotBookingsScreen extends ConsumerStatefulWidget {
  const SlotBookingsScreen({super.key, required this.slot, required this.date});
  final TimeSlot slot;
  final DateTime date;

  @override
  ConsumerState<SlotBookingsScreen> createState() => _SlotBookingsScreenState();
}

class _SlotBookingsScreenState extends ConsumerState<SlotBookingsScreen> {
  List<SlotBooking>? _bookings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bookings = await ref
          .read(scheduleRepositoryProvider)
          .fetchSlotBookings(widget.slot.id, widget.date);
      if (!mounted) return;
      setState(() => _bookings = bookings);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(widget.slot.label)),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : _bookings == null
            ? const Center(child: CircularProgressIndicator())
            : _bookings!.isEmpty
            ? const Center(
                child: Text(
                  'No one booked for this day.',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final b in _bookings!)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            b.memberName,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            b.memberCode,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
