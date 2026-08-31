import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../providers/plans_provider.dart';
import '../../../core/api/api_exception.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cFieldBg = Color(0xFFF5F6F7);
const Color _cCardBg = Colors.white;
const Color _cAccentTeal = Color(0xFF0F6E56);
const Color _cErrorText = Color(0xFF9E3125);
const Color _cErrorBg = Color(0xFFFCEBE8);
const Color _cDisabledBg = Color(0xFFE2E5E3);

const List<String> _durationUnits = ['DAY', 'WEEK', 'MONTH', 'YEAR'];

class ManagePlansScreen extends ConsumerWidget {
  const ManagePlansScreen({super.key, required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allPlansProvider(gymId));

    return Scaffold(
      backgroundColor: _cPageBg,
      appBar: AppBar(
        backgroundColor: _cPageBg,
        elevation: 0,
        title: const Text(
          'Manage Plans',
          style: TextStyle(color: _cInk, fontWeight: FontWeight.w500),
        ),
        iconTheme: const IconThemeData(color: _cInk),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: plansAsync.when(
                  data: (plans) {
                    if (plans.isEmpty) {
                      return const Center(
                        child: Text(
                          'No plans yet',
                          style: TextStyle(color: _cSubtle),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: plans.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _PlanTile(plan: plans[index], gymId: gymId),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Something went wrong: $error')),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _openPlanForm(context, gymId: gymId),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cInk,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    'Add Plan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openPlanForm(
  BuildContext context, {
  required String gymId,
  MembershipPlan? existing,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _cPageBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PlanFormSheet(gymId: gymId, existing: existing),
    ),
  );
}

class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.plan, required this.gymId});

  final MembershipPlan plan;
  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pesos = plan.priceCentavos / 100;
    final subtitle =
        '₱${pesos.toStringAsFixed(2)} / ${plan.durationValue} '
        '${plan.durationUnit.toLowerCase()}'
        '${plan.durationValue == 1 ? '' : 's'}'
        '${plan.category.isEmpty ? '' : ' · ${plan.category}'}';

    return Container(
      decoration: BoxDecoration(
        color: _cCardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _cInk,
                      ),
                    ),
                    if (!plan.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _cErrorBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Inactive',
                          style: TextStyle(fontSize: 10, color: _cErrorText),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: _cMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: _cSubtle),
            onPressed: () =>
                _openPlanForm(context, gymId: gymId, existing: plan),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: _cErrorText,
            ),
            onPressed: () => _confirmDelete(context, ref, plan),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    MembershipPlan plan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${plan.name}"?'),
        content: const Text(
          'This removes the plan entirely. If members have used it '
          'before, turning off Active (edit → Active) is usually safer '
          'than deleting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(plansRepositoryProvider).deletePlan(plan.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't delete — check your connection."),
          ),
        );
      }
    }
  }
}

class _PlanFormSheet extends ConsumerStatefulWidget {
  const _PlanFormSheet({required this.gymId, this.existing});

  final String gymId;
  final MembershipPlan? existing;

  @override
  ConsumerState<_PlanFormSheet> createState() => _PlanFormSheetState();
}

class _PlanFormSheetState extends ConsumerState<_PlanFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _durationValueCtrl;
  late String _durationUnit;
  late bool _isActive;

  bool _isSubmitting = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _priceCtrl = TextEditingController(
      text: e != null ? (e.priceCentavos / 100).toStringAsFixed(2) : '',
    );
    _durationValueCtrl = TextEditingController(
      text: e != null ? e.durationValue.toString() : '1',
    );
    _durationUnit = e?.durationUnit ?? 'MONTH';
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _priceCtrl.dispose();
    _durationValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final durationValue = int.tryParse(_durationValueCtrl.text.trim());

    if (name.isEmpty || price == null || durationValue == null) {
      setState(() => _error = 'Fill in name, price, and duration.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final repo = ref.read(plansRepositoryProvider);
      if (_isEditing) {
        await repo.updatePlan(
          id: widget.existing!.id,
          gymId: widget.gymId,
          name: name,
          category: _categoryCtrl.text.trim(),
          durationValue: durationValue,
          durationUnit: _durationUnit,
          price: price,
          // Day pass isn't exposed in this form — the only day-pass plans
          // are the ones seeded at signup; plans created here are always
          // regular (non-day-pass) plans.
          isDayPass: false,
          isActive: _isActive,
        );
      } else {
        await repo.createPlan(
          gymId: widget.gymId,
          name: name,
          category: _categoryCtrl.text.trim(),
          durationValue: durationValue,
          durationUnit: _durationUnit,
          price: price,
          isDayPass: false,
          isActive: _isActive,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          // Prefer the backend's specific field error (e.g. the
          // duplicate-name message from MembershipPlanSerializer) over
          // the generic fallback, since it tells the user exactly what
          // to fix.
          String? specificMessage;
          final fieldErrors = e.fieldErrors;
          if (fieldErrors != null && fieldErrors.isNotEmpty) {
            final firstList = fieldErrors.values.first;
            if (firstList.isNotEmpty) {
              specificMessage = firstList.first;
            }
          }
          _error =
              specificMessage ??
              e.message ??
              "Couldn't save — check the fields and try again.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = "Couldn't save — check your connection and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _cDisabledBg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            _isEditing ? 'Edit plan' : 'Add plan',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _cInk,
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cErrorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: _cErrorText, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ],

          _field('Name', _nameCtrl, hint: 'Monthly'),
          const SizedBox(height: 12),
          _field('Category', _categoryCtrl, hint: 'Student, Regular'),
          const SizedBox(height: 12),
          _field(
            'Price',
            _priceCtrl,
            hint: '650',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _field(
                  'Duration',
                  _durationValueCtrl,
                  hint: '1',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _cFieldBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _durationUnit,
                      isExpanded: true,
                      items: _durationUnits
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _durationUnit = v ?? _durationUnit),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              "Off hides this plan from new members, but keeps it in old records.",
              style: TextStyle(fontSize: 11, color: _cMuted),
            ),
            value: _isActive,
            activeThumbColor: _cAccentTeal,
            onChanged: (v) => setState(() => _isActive = v),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _cInk,
                      side: const BorderSide(color: _cDisabledBg),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cInk,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEditing ? 'Save changes' : 'Add plan'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _cSubtle,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _cFieldBg,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: !_isSubmitting,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _cMuted, fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}
