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
      appBar: AppBar(title: const Text('Results')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  for (var i = 0; i < _rows.length; i++)
                    _ResultRowCard(
                      row: _rows[i],
                      onRemove: () => _removeRow(i),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Add row'),
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
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentTeal,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Results'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResultRowCard extends StatelessWidget {
  const _ResultRowCard({required this.row, required this.onRemove});
  final _ResultRowInput row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: TextField(
                  controller: row.rankController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Rank'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.scoreController,
                  decoration: const InputDecoration(
                    labelText: 'Score (e.g. 82kg, 3:41)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
