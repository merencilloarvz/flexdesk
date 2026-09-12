import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../data/schedule_repository.dart';
import '../providers/schedule_providers.dart';

class TimeSlotEditScreen extends ConsumerStatefulWidget {
  const TimeSlotEditScreen({super.key, this.slot});

  final TimeSlot? slot;

  @override
  ConsumerState<TimeSlotEditScreen> createState() => _TimeSlotEditScreenState();
}

class _TimeSlotEditScreenState extends ConsumerState<TimeSlotEditScreen> {
  late final TextEditingController _labelController;
  late final TextEditingController _capacityController;
  late final TextEditingController _coachController;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final Set<int> _days = {};
  bool _isActive = true;
  bool _saving = false;
  String? _generalError;
  String? _capacityError;

  bool get _isEditing => widget.slot != null;

  @override
  void initState() {
    super.initState();
    final slot = widget.slot;
    _labelController = TextEditingController(text: slot?.label ?? '');
    _capacityController = TextEditingController(
      text: slot != null ? slot.capacity.toString() : '',
    );
    _coachController = TextEditingController(text: slot?.coachName ?? '');
    if (slot != null) {
      _startTime = _parseTime(slot.startTime);
      _endTime = _parseTime(slot.endTime);
      _days.addAll(slot.days);
      _isActive = slot.isActive;
    }
  }

  TimeOfDay _parseTime(String hhmmss) {
    final parts = hhmmss.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  void dispose() {
    _labelController.dispose();
    _capacityController.dispose();
    _coachController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String? _durationLabel() {
    if (_startTime == null || _endTime == null) return null;
    final startMin = _startTime!.hour * 60 + _startTime!.minute;
    var endMin = _endTime!.hour * 60 + _endTime!.minute;
    if (endMin <= startMin) return null;
    final diff = endMin - startMin;
    if (diff < 60) return '$diff mins';
    final hrs = diff ~/ 60;
    final mins = diff % 60;
    return mins == 0 ? '$hrs hr${hrs == 1 ? '' : 's'}' : '$hrs hr $mins mins';
  }

  Future<void> _save() async {
    setState(() {
      _generalError = null;
      _capacityError = null;
    });

    final label = _labelController.text.trim();
    final capacity = int.tryParse(_capacityController.text.trim());

    if (label.isEmpty) {
      setState(() => _generalError = 'Enter a label.');
      return;
    }
    if (_startTime == null || _endTime == null) {
      setState(() => _generalError = 'Pick a start and end time.');
      return;
    }
    if (capacity == null || capacity < 1) {
      setState(() => _capacityError = 'Enter a capacity of at least 1.');
      return;
    }
    if (_days.isEmpty) {
      setState(() => _generalError = 'Pick at least one day.');
      return;
    }

    setState(() => _saving = true);
    final daysStr = (_days.toList()..sort()).join(',');
    final coachName = _coachController.text.trim();
    final repo = ref.read(scheduleRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updateTimeSlot(widget.slot!.id, {
          'label': label,
          'start_time': _formatTime(_startTime!),
          'end_time': _formatTime(_endTime!),
          'capacity': capacity,
          'days_of_week': daysStr,
          'is_active': _isActive,
          'coach_name': coachName,
        });
      } else {
        await repo.createTimeSlot(
          label: label,
          startTime: _formatTime(_startTime!),
          endTime: _formatTime(_endTime!),
          capacity: capacity,
          daysOfWeek: daysStr,
          coachName: coachName,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final capacityErrors = e.fieldErrors?['capacity'];
      setState(() {
        _saving = false;
        if (capacityErrors != null && capacityErrors.isNotEmpty) {
          _capacityError = capacityErrors.first;
        } else {
          _generalError = e.message;
        }
      });
    }
  }

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  void _discard() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final duration = _durationLabel();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _isEditing ? 'Edit Time Slot' : 'Add Time Slot',
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _SectionCard(
              label: 'SLOT LABEL / DEDICATED ACTIVITY',
              required: true,
              child: Row(
                children: [
                  const Icon(
                    Icons.fitness_center,
                    size: 16,
                    color: AppColors.accentTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentTeal,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Morning CrossFit',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _SectionCard(
              label: 'TIME RANGE',
              trailing: duration != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 12,
                          color: AppColors.accentTeal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          duration,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentTeal,
                          ),
                        ),
                      ],
                    )
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'START TIME',
                      value: _startTime,
                      onTap: () => _pickTime(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: 'END TIME',
                      value: _endTime,
                      onTap: () => _pickTime(false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _SectionCard(
              label: 'CLASS CAPACITY',
              trailing: const Text(
                'Spots per class',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.groups_outlined,
                    size: 18,
                    color: AppColors.accentTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _capacityController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. 10',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        errorText: _capacityError,
                      ),
                    ),
                  ),
                  const Text(
                    'members',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _SectionCard(
              label: 'RECURRING DAYS',
              sublabel: 'Class will automatically repeat',
              trailing: Text(
                '${_days.length} days / wk',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentTeal,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 7; i++)
                    _DayChip(
                      label: _dayLabels[i],
                      selected: _days.contains(i + 1),
                      onTap: () => setState(() {
                        final day = i + 1;
                        if (_days.contains(day)) {
                          _days.remove(day);
                        } else {
                          _days.add(day);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentTealBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 18,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _coachController,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Assign a coach (optional)',
                        hintStyle: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Text(
                    _coachController.text.trim().isEmpty ? 'Add' : 'Change',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentTeal,
                    ),
                  ),
                ],
              ),
            ),

            if (_isEditing) ...[
              const SizedBox(height: 12),
              _SectionCard(
                label: 'STATUS',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Active',
                    style: TextStyle(color: AppColors.ink, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Turn off instead of deleting — history stays, switch it back on later.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  value: _isActive,
                  activeThumbColor: AppColors.accentTeal,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ),
            ],

            if (_generalError != null) ...[
              const SizedBox(height: 12),
              Text(
                _generalError!,
                style: const TextStyle(color: AppColors.errorText),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
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
                    : Text(_isEditing ? 'Save Changes' : 'Create Slot'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _saving ? null : _discard,
                child: const Text(
                  'Discard Draft',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.label,
    required this.child,
    this.sublabel,
    this.trailing,
    this.required = false,
  });

  final String label;
  final String? sublabel;
  final Widget child;
  final Widget? trailing;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.subtle,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(color: AppColors.errorText, fontSize: 10),
                ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel!,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.fieldBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value != null ? value!.format(context) : 'Select',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: value != null ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
                const Icon(
                  Icons.access_time,
                  size: 15,
                  color: AppColors.accentTeal,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
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
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTeal : AppColors.fieldBg,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
