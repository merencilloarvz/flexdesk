import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import '../../widgets/comments_section.dart';
import 'event_edit_screen.dart';
import 'event_results_display_screen.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  Event? _event;
  List<Registrant>? _registrants;
  String? _error;
  String? _busyRegistrationId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(communityRepositoryProvider);
    try {
      final event = await repo.fetchEvent(widget.eventId);
      final registrants = await repo.fetchRegistrants(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _registrants = registrants;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _confirmMarkPaid(Registrant r) async {
    final symbol = _currencySymbol();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as paid?'),
        content: Text(
          'Mark ${r.memberName} as paid, $symbol${centavosToDecimalString(r.amountDueCentavos)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyRegistrationId = r.id);
    try {
      await ref.read(communityRepositoryProvider).markPaid(r.id);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    setState(() => _busyRegistrationId = null);
    await _load();
  }

  Future<void> _markUnpaid(Registrant r) async {
    setState(() => _busyRegistrationId = r.id);
    try {
      await ref.read(communityRepositoryProvider).markUnpaid(r.id);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    setState(() => _busyRegistrationId = null);
    await _load();
  }

  String _subtitle(Event event) {
    final parts = [DateFormat('EEE, MMM d').format(event.eventDate)];
    if (event.startTime != null) {
      final t = event.startTime!.split(':');
      final time = DateTime(0, 1, 1, int.parse(t[0]), int.parse(t[1]));
      parts.add(DateFormat('h:mm a').format(time));
    }
    if (event.locationText.isNotEmpty) parts.add(event.locationText);
    return parts.join(' · ');
  }

  String _currencySymbol() {
    final authState = ref.read(authControllerProvider);
    return authState is AuthAuthenticated
        ? currencySymbol(authState.user.gym?.currency ?? 'PHP')
        : '₱';
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final registrants = _registrants ?? const <Registrant>[];
    final collected = registrants
        .where((r) => r.paymentStatus == 'paid')
        .fold<int>(0, (sum, r) => sum + r.amountDueCentavos);
    final outstanding = registrants
        .where((r) => r.paymentStatus != 'paid')
        .fold<int>(0, (sum, r) => sum + r.amountDueCentavos);
    final symbol = _currencySymbol();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: Text(
          event?.title ?? 'Event',
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
        actions: [
          if (event != null)
            IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                color: AppColors.accentTeal,
              ),
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EventEditScreen(event: event),
                  ),
                );
                if (changed == true) _load();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : event == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accentTeal,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    if (event.isCanceled) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.errorBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'This event is cancelled.',
                          style: TextStyle(
                            color: AppColors.errorText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(event),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.subtle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _TotalCard(
                            label: 'Collected',
                            amount:
                                '$symbol${centavosToDecimalString(collected)}',
                            color: AppColors.accentTeal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TotalCard(
                            label: 'Outstanding',
                            amount:
                                '$symbol${centavosToDecimalString(outstanding)}',
                            color: AppColors.expiringBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text(
                          'Registrants',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${registrants.length})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (registrants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No one has registered yet.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    for (final r in registrants)
                      _RegistrantTile(
                        registrant: r,
                        busy: _busyRegistrationId == r.id,
                        symbol: symbol,
                        onTap: () => r.paymentStatus == 'paid'
                            ? _markUnpaid(r)
                            : _confirmMarkPaid(r),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventResultsDisplayScreen(
                                eventId: event.id,
                              ),
                            ),
                          );
                          _load();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Scoreboard & Results',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Staff see a delete icon on every comment here
                    // (moderation) — the server decides via can_delete.
                    CommentsSection(
                      itemType: CommunityItemType.event,
                      itemId: event.id,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

class _RegistrantTile extends StatelessWidget {
  const _RegistrantTile({
    required this.registrant,
    required this.busy,
    required this.symbol,
    required this.onTap,
  });
  final Registrant registrant;
  final bool busy;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paid = registrant.paymentStatus == 'paid';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: busy ? null : onTap,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.accentTealBg,
          child: Text(
            _initialsFor(registrant.memberName),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accentTeal,
            ),
          ),
        ),
        title: Text(
          registrant.memberName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        trailing: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: paid ? AppColors.accentTealBg : AppColors.fieldBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  paid
                      ? 'Paid $symbol${centavosToDecimalString(registrant.amountDueCentavos)}'
                      : 'Unpaid',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: paid ? AppColors.accentTeal : AppColors.subtle,
                  ),
                ),
              ),
      ),
    );
  }
}
