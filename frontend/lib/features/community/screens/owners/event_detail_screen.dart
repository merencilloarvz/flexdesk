import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';
import 'event_edit_screen.dart';
import 'event_results_screen.dart';

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

  String _currencySymbol() {
    final authState = ref.read(authControllerProvider);
    return authState is AuthAuthenticated
        ? currencySymbol(authState.user.gym.currency)
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
                color: AppColors.accentBlue,
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
                color: AppColors.accentBlue,
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
                    Row(
                      children: [
                        Expanded(
                          child: _TotalCard(
                            label: 'Collected',
                            amount:
                                '$symbol${centavosToDecimalString(collected)}',
                            color: AppColors.accentBlue,
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
                    if (event.eventDate.isBefore(DateTime.now())) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  EventResultsScreen(eventId: event.id),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentBlue,
                          ),
                          child: const Text('Enter Results'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Registrants',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
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
        title: Text(
          registrant.memberName,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
        subtitle: Text(
          registrant.memberCode,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        trailing: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$symbol${centavosToDecimalString(registrant.amountDueCentavos)}',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: paid ? AppColors.accentBlue : AppColors.expiringBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      paid ? 'Paid' : 'Unpaid',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
