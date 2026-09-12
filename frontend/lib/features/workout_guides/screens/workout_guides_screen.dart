import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../shell/app_shell.dart';
import '../models/workout_guide.dart';
import '../providers/workout_guides_providers.dart';
import '../widgets/guide_frame.dart';
import 'guide_detail_screen.dart';

/// Top-level "Workout Guides" tab — its own nav destination, not a
/// Community segment. Matches the header/scaffold pattern used by the
/// other top-level screens (see CommunityScreen's _buildHeader) so it
/// doesn't look bolted on.
class WorkoutGuidesScreen extends ConsumerWidget {
  const WorkoutGuidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guidesAsync = ref.watch(workoutGuidesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(
              child: guidesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text(
                    'Couldn\u2019t load guides.',
                    style: const TextStyle(color: AppColors.errorText),
                  ),
                ),
                data: (_) {
                  final filtered = ref.watch(filteredWorkoutGuidesProvider);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _MuscleGroupFilterRow(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? const _EmptyFilterState()
                            : GridView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  AppShell.reservedNavHeight + 24,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 0.82,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) =>
                                    _GuideCard(guide: filtered[index]),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F6E56),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'IRON WORKS CEBU • GUIDES',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D4B39),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Workout Guides',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E1A13),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Illustrated, step-by-step form guides you can follow offline.',
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF6B7570),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _MuscleGroupFilterRow extends ConsumerWidget {
  const _MuscleGroupFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(muscleGroupFiltersProvider);
    final selected = ref.watch(selectedMuscleGroupProvider);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = groups[index];
          final isSelected = selected == group;
          return InkWell(
            onTap: () =>
                ref.read(selectedMuscleGroupProvider.notifier).state = group,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0D4B39) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF0D4B39)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Text(
                group,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.guide});

  final WorkoutGuide guide;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GuideDetailScreen(slug: guide.slug),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFFF1F5F3),
                padding: const EdgeInsets.all(12),
                child: GuideFrame(assetPath: guide.thumbnailAsset),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guide.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0E1A13),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    guide.muscleGroup,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF6B7570),
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

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No guides in this muscle group yet.',
          style: TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }
}
