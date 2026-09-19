import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';

class EventResultsScreen extends ConsumerStatefulWidget {
  const EventResultsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventResultsScreen> createState() => _EventResultsScreenState();
}

class _ResultRowInput {
  _ResultRowInput({
    String? displayName,
    int? rank,
    String? scoreText,
    String? note,
  }) : nameController = TextEditingController(text: displayName ?? ''),
       rankController = TextEditingController(text: rank?.toString() ?? ''),
       scoreController = TextEditingController(text: scoreText ?? ''),
       noteController = TextEditingController(text: note ?? '');

  final TextEditingController nameController;
  final TextEditingController rankController;
  final TextEditingController scoreController;
  final TextEditingController noteController;

  void dispose() {
    nameController.dispose();
    rankController.dispose();
    scoreController.dispose();
    noteController.dispose();
  }
}

class _EventResultsScreenState extends ConsumerState<EventResultsScreen> {
  final List<_ResultRowInput> _rows = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await ref
          .read(communityRepositoryProvider)
          .fetchResults(widget.eventId);
      if (!mounted) return;
      setState(() {
        if (results.isEmpty) {
          _rows.add(_ResultRowInput(rank: 1));
        } else {
          for (final r in results) {
            _rows.add(
              _ResultRowInput(
                displayName: r.displayName,
                rank: r.rank,
                scoreText: r.scoreText,
                note: r.note,
              ),
            );
          }
        }
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

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() =>
      setState(() => _rows.add(_ResultRowInput(rank: _rows.length + 1)));

  void _removeRow(int index) => setState(() {
    _rows[index].dispose();
    _rows.removeAt(index);
  });

  Future<void> _submit() async {
    setState(() => _error = null);

    final entries = <EventResultRow>[];
    final ranksSeen = <int>{};
    for (final row in _rows) {
      final name = row.nameController.text.trim();
      final rank = int.tryParse(row.rankController.text.trim());
      if (name.isEmpty) {
        setState(() => _error = 'Every row needs a name.');
        return;
      }
      if (rank == null || rank < 1) {
        setState(() => _error = 'Every row needs a rank of at least 1.');
        return;
      }
      // Client-side rank-uniqueness check, ahead of the server's own —
      // the server replaces the whole set atomically and rejects
      // duplicates outright, which would mean losing everything just
      // typed. Catching it here saves that.
      if (!ranksSeen.add(rank)) {
        setState(
          () => _error =
              'Rank $rank is used more than once — ranks must be unique.',
        );
        return;
      }
      entries.add(
        EventResultRow(
          displayName: name,
          rank: rank,
          scoreText: row.scoreController.text.trim(),
          note: row.noteController.text.trim(),
        ),
      );
    }

    if (entries.isEmpty) {
      setState(() => _error = 'Add at least one result.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(communityRepositoryProvider)
          .submitResults(widget.eventId, entries);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Results',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            const Text(
              'Enter competitor scores & ranks',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w400,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_rows.length} ${_rows.length == 1 ? 'Entry' : 'Entries'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.linkGreen,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  for (var i = 0; i < _rows.length; i++)
                    _ResultRowCard(
                      rank: i + 1,
                      row: _rows[i],
                      onRemove: () => _removeRow(i),
                    ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addRow,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Competitor Row'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.linkGreen,
                        backgroundColor: AppColors.successBg,
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.errorText),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox.shrink()
                          : const Icon(Icons.check, size: 18),
                      label: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Results'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Updates will immediately reflect on the public leaderboard',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResultRowCard extends StatelessWidget {
  const _ResultRowCard({
    required this.rank,
    required this.row,
    required this.onRemove,
  });
  final int rank;
  final _ResultRowInput row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.accentTeal,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'RANK #$rank',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: AppColors.accentTeal,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: _labeledField(
                  label: 'RANK',
                  controller: row.rankController,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _labeledField(
                  label: 'COMPETITOR NAME',
                  controller: row.nameController,
                  hint: 'e.g. Juan Dela Cruz',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeledField(
                  label: 'SCORE',
                  controller: row.scoreController,
                  hint: 'e.g. 82kg, 3:41',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _labeledField(
                  label: 'NOTE (OPTIONAL)',
                  controller: row.noteController,
                  hint: 'Rx, penalty, etc.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: AppColors.subtle,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.fieldBg,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 14, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
