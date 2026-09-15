import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../providers/plans_provider.dart';
import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';

const Color _cPageBg = Color(0xFFF4F7F8);
const Color _cInk = Color(0xFF071A14);
const Color _cSubtle = Color(0xFF66736E);
const Color _cMuted = Color(0xFF87938F);
const Color _cFieldBg = Color(0xFFF0F3F3);
const Color _cCardBg = Colors.white;
const Color _cAccentTeal = Color(0xFF005C47);
const Color _cAccentTealBg = Color(0xFFE1F5EE);
const Color _cErrorText = Color(0xFFFF6173);
const Color _cErrorBg = Color(0xFFFCEBED);
const Color _cDisabledBg = Color(0xFFDDE4E1);

const List<String> _durationUnits = ['DAY', 'WEEK', 'MONTH', 'YEAR'];

enum _StatusFilter { all, active, inactive }

class ManagePlansScreen extends ConsumerStatefulWidget {
  const ManagePlansScreen({
    super.key,
    required this.gymId,
    this.firstRun = false,
  });

  final String gymId;
  final bool firstRun;

  @override
  ConsumerState<ManagePlansScreen> createState() => _ManagePlansScreenState();
}

class _ManagePlansScreenState extends ConsumerState<ManagePlansScreen> {
  _StatusFilter _filter = _StatusFilter.all;
  bool _continuing = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPlans();
    });
  }

  Future<void> _refreshPlans() async {
    try {
      await ref.read(plansRepositoryProvider).refreshPlans(widget.gymId);
    } catch (_) {
      // Keep local cache visible if offline.
    }
  }

  Future<void> _continueFromFirstRun() async {
    if (_continuing) return;

    setState(() => _continuing = true);

    try {
      final updatedUser = await ref.read(authApiProvider).me();

      ref.read(authControllerProvider.notifier).applyUser(updatedUser);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't continue — check your connection."),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _continuing = false);
      }
    }
  }

  Future<void> _logout() async {
    try {
      await ref.read(authControllerProvider.notifier).logout(force: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(allPlansProvider(widget.gymId));

    final hasPricedPlan =
        plansAsync.asData?.value.any((p) => p.priceCentavos > 0) ?? false;

    return Scaffold(
      backgroundColor: _cPageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Column(
            children: [
              _buildHeader(context),

              if (widget.firstRun)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: const Text(
                    'These are the plans members will be signed up to — '
                    'set the prices your gym charges.',
                    style: TextStyle(fontSize: 13, color: _cSubtle),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildFilterTabs(),
              ),

              const SizedBox(height: 10),

              Expanded(
                child: plansAsync.when(
                  data: (allPlans) {
                    var plans = allPlans.where((p) => !p.isDayPass).toList();

                    if (_filter == _StatusFilter.active) {
                      plans = plans.where((p) => p.isActive).toList();
                    } else if (_filter == _StatusFilter.inactive) {
                      plans = plans.where((p) => !p.isActive).toList();
                    }

                    if (plans.isEmpty) {
                      return const Center(
                        child: Text(
                          'No plans yet',
                          style: TextStyle(color: _cSubtle),
                        ),
                      );
                    }

                    return RefreshIndicator(
                      color: _cAccentTeal,
                      onRefresh: _refreshPlans,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(1, 0, 1, 4),
                        itemCount: plans.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 7),
                        itemBuilder: (context, index) {
                          return _PlanTile(
                            plan: plans[index],
                            gymId: widget.gymId,
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: _cAccentTeal),
                  ),
                  error: (error, _) => Center(
                    child: Text(
                      'Something went wrong: $error',
                      style: const TextStyle(color: _cSubtle),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: widget.firstRun
                      ? FilledButton(
                          onPressed: hasPricedPlan && !_continuing
                              ? _continueFromFirstRun
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _cAccentTeal,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _cDisabledBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _continuing
                              ? const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save and continue',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        )
                      : FilledButton.icon(
                          onPressed: () {
                            openPlanForm(context, gymId: widget.gymId);
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Add New Plan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _cAccentTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          if (!widget.firstRun)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => context.pop(),
              icon: const Icon(Icons.chevron_left, size: 23, color: _cSubtle),
            ),

          if (!widget.firstRun) const SizedBox(width: 1),

          Expanded(
            child: Text(
              widget.firstRun ? 'Set your pricing' : 'Manage Plans',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _cInk,
              ),
            ),
          ),

          if (widget.firstRun)
            TextButton(
              onPressed: _logout,
              style: TextButton.styleFrom(
                foregroundColor: _cAccentTeal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(
                'Log out',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 27,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _cFieldBg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FilterTab(
              label: 'All',
              selected: _filter == _StatusFilter.all,
              onTap: () {
                setState(() => _filter = _StatusFilter.all);
              },
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: 'Active',
              selected: _filter == _StatusFilter.active,
              onTap: () {
                setState(() => _filter = _StatusFilter.active);
              },
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: 'Inactive',
              selected: _filter == _StatusFilter.inactive,
              onTap: () {
                setState(() => _filter = _StatusFilter.inactive);
              },
            ),
          ),
        ],
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _cAccentTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : _cMuted,
          ),
        ),
      ),
    );
  }
}

/// Public entry point used by other screens.
void openPlanForm(
  BuildContext context, {
  required String gymId,
  MembershipPlan? existing,
}) {
  _openPlanForm(context, gymId: gymId, existing: existing);
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

  String _durationLabel() {
    final value = plan.durationValue;
    final unit = plan.durationUnit.toUpperCase();

    if (unit == 'DAY') {
      return value == 1 ? '1 day access' : '$value days';
    }

    if (unit == 'WEEK') {
      return value == 1 ? '1 week' : '$value weeks';
    }

    if (unit == 'MONTH') {
      return value == 1 ? '1 month' : '$value months';
    }

    if (unit == 'YEAR') {
      return value == 1 ? '1 full year' : '$value years';
    }

    return '$value ${unit.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pesos = plan.priceCentavos / 100;

    return Container(
      decoration: BoxDecoration(
        color: _cCardBg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE5EBE9), width: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 7, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _cInk,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              SizedBox(
                width: 25,
                height: 25,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _openPlanForm(context, gymId: gymId, existing: plan);
                  },
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: Color(0xFF8A9DA5),
                  ),
                ),
              ),

              SizedBox(
                width: 25,
                height: 25,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _confirmDelete(context, ref, plan);
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 15,
                    color: _cErrorText,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 1),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₱${pesos.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _cInk,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '/ ${_durationLabel()}',
                style: const TextStyle(fontSize: 7, color: _cMuted),
              ),
            ],
          ),

          const SizedBox(height: 5),

          Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: plan.isActive ? const Color(0xFF00A878) : _cErrorText,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                plan.isActive ? 'Active Tier' : 'Inactive Tier',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: plan.isActive ? _cAccentTeal : _cErrorText,
                ),
              ),
            ],
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
          'This removes the plan entirely. '
          'If members have used it before, '
          'turning off Active is usually safer '
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
    } catch (_) {
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

const List<String> _categoryPresets = ['Student', 'Regular', 'VIP', 'Trainer'];

class _PlanFormSheetState extends ConsumerState<_PlanFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _durationValueCtrl;

  late String _durationUnit;
  late bool _isActive;
  late bool _customCategoryMode;

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

    final currentCategory = e?.category ?? '';

    _customCategoryMode =
        currentCategory.isNotEmpty &&
        !_categoryPresets.any(
          (p) => p.toLowerCase() == currentCategory.toLowerCase(),
        );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _priceCtrl.dispose();
    _durationValueCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(String preset) {
    setState(() {
      _customCategoryMode = false;
      _categoryCtrl.text = preset;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();

    final price = double.tryParse(_priceCtrl.text.trim());

    final durationValue = int.tryParse(_durationValueCtrl.text.trim());

    if (name.isEmpty || price == null || durationValue == null) {
      setState(() {
        _error = 'Fill in name, price, and duration.';
      });
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

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;

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
    } catch (_) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              color: _cInk,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Edit Plan' : 'Add New Plan',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Membership Tier',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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

                _field('Plan Name', _nameCtrl, hint: 'Monthly Regular'),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _cSubtle,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _customCategoryMode = !_customCategoryMode;

                        if (_customCategoryMode) {
                          _categoryCtrl.clear();
                        }
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _customCategoryMode ? Icons.close : Icons.add,
                            size: 14,
                            color: _cAccentTeal,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _customCategoryMode ? 'Use preset' : 'Add Custom',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _cAccentTeal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                if (_customCategoryMode)
                  _field('', _categoryCtrl, hint: 'e.g. Senior, Weekend Pass')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in _categoryPresets)
                        _CategoryChip(
                          label: preset,
                          selected:
                              _categoryCtrl.text.toLowerCase() ==
                              preset.toLowerCase(),
                          onTap: () => _selectPreset(preset),
                        ),
                    ],
                  ),

                const SizedBox(height: 16),

                _field(
                  'Price (PHP)',
                  _priceCtrl,
                  hint: '650',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.currency_exchange,
                ),

                const SizedBox(height: 16),

                const Text(
                  'Duration Length & Unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cSubtle,
                  ),
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Expanded(child: _durationField()),
                    const SizedBox(width: 12),
                    Expanded(child: _durationDropdown()),
                  ],
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _cCardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cDisabledBg),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Text(
                              'Active Plan',
                              style: TextStyle(fontSize: 14, color: _cInk),
                            ),
                            if (_isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F6ED),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F7A4D),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Switch(
                        value: _isActive,
                        activeThumbColor: _cAccentTeal,
                        onChanged: _isSubmitting
                            ? null
                            : (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'Off hides this plan from new members, but keeps it in old records.',
                  style: TextStyle(fontSize: 11, color: _cMuted),
                ),

                const SizedBox(height: 20),

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
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _save,
                          icon: _isSubmitting
                              ? const SizedBox.shrink()
                              : const Icon(Icons.check, size: 18),
                          label: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isEditing ? 'Save changes' : 'Save Plan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _cAccentTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
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

  Widget _durationField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _cFieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _durationValueCtrl,
        keyboardType: TextInputType.number,
        enabled: !_isSubmitting,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 15),
        decoration: const InputDecoration(
          hintText: '1',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _durationDropdown() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _cFieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _durationUnit,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: _cAccentTeal),
          items: _durationUnits
              .map(
                (u) => DropdownMenuItem(
                  value: u,
                  child: Text('${u[0]}${u.substring(1).toLowerCase()}(s)'),
                ),
              )
              .toList(),
          onChanged: _isSubmitting
              ? null
              : (v) => setState(() => _durationUnit = v ?? _durationUnit),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    IconData? prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _cSubtle,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _cFieldBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: 17, color: _cAccentTeal),
                const SizedBox(width: 8),
              ],
              Expanded(
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
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _cAccentTealBg : _cFieldBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _cAccentTeal : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? _cAccentTeal : _cSubtle,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check, size: 13, color: _cAccentTeal),
            ],
          ],
        ),
      ),
    );
  }
}
