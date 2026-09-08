import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/colors.dart';
import '../../members/providers/plans_provider.dart';

// The two categories this screen always offers, regardless of whether a
// matching plan exists yet. If a plan with this category is already in
// dayPassPlans, its real price pre-fills the field and Save updates it.
// If not, Save CREATES it — no trip to Manage Plans required. The price
// is still a real, synced MembershipPlan row either way, never a local
// disconnected number — that's the thing D2 specifically fixed.
const _defaultWalkInCategories = ['Student', 'Regular'];

/// Edits walk-in day-pass prices directly from this screen. Shows the two
/// default categories always, plus any other day-pass plan that already
/// exists with a different category (so a custom category set up
/// elsewhere is still editable here too).
Future<void> showEditWalkInPricesSheet(
  BuildContext context, {
  required String gymId,
  required List<MembershipPlan> dayPassPlans,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        child: _EditWalkInPricesSheet(gymId: gymId, dayPassPlans: dayPassPlans),
      ),
    ),
  );
}

class _EditWalkInPricesSheet extends ConsumerStatefulWidget {
  const _EditWalkInPricesSheet({
    required this.gymId,
    required this.dayPassPlans,
  });
  final String gymId;
  final List<MembershipPlan> dayPassPlans;

  @override
  ConsumerState<_EditWalkInPricesSheet> createState() =>
      _EditWalkInPricesSheetState();
}

class _EditWalkInPricesSheetState
    extends ConsumerState<_EditWalkInPricesSheet> {
  late final List<String> _categories;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  String? _error;

  MembershipPlan? _existingFor(String category) {
    for (final p in widget.dayPassPlans) {
      if (p.category.toLowerCase() == category.toLowerCase()) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Default two categories always shown, plus any other day-pass
    // category that already exists but isn't one of the defaults.
    final extraCategories = widget.dayPassPlans
        .map((p) => p.category)
        .where((c) => c.isNotEmpty)
        .where(
          (c) => !_defaultWalkInCategories.any(
            (d) => d.toLowerCase() == c.toLowerCase(),
          ),
        )
        .toSet();
    _categories = [..._defaultWalkInCategories, ...extraCategories];

    _controllers = {
      for (final category in _categories)
        category: TextEditingController(
          text: (() {
            final existing = _existingFor(category);
            return existing == null
                ? '0'
                : (existing.priceCentavos / 100).toStringAsFixed(0);
          })(),
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(plansRepositoryProvider);
      for (final category in _categories) {
        final text = _controllers[category]!.text.trim();
        final pesos = double.tryParse(text);
        if (pesos == null || pesos < 0) {
          setState(() {
            _saving = false;
            _error = 'Enter a valid price for every category.';
          });
          return;
        }

        final existing = _existingFor(category);
        if (existing == null) {
          // Doesn't exist yet — create it as a real day-pass plan, right
          // from here, no separate Manage Plans step needed.
          await repo.createPlan(
            gymId: widget.gymId,
            name: category,
            category: category,
            durationValue: 1,
            durationUnit: 'DAY',
            price: pesos,
            isDayPass: true,
          );
        } else {
          final currentPesos = existing.priceCentavos / 100;
          if (pesos != currentPesos) {
            await repo.updatePlan(
              id: existing.id,
              gymId: widget.gymId,
              price: pesos,
            );
          }
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save — check your connection and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accentBlueBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.accentBlue,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Edit walk-in prices',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 42),
            child: Text(
              'Configure day-pass rates for walk-in visitors',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 20),
          for (final category in _categories) ...[
            Text(
              category,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.pageBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _controllers[category],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '₱ ',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: AppColors.errorText, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
