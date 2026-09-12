import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/colors.dart';
import '../../data/community_repository.dart';
import '../../providers/community_providers.dart';

class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key, this.event});
  final Event? event;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _feeController;
  late final TextEditingController _prizeController;
  late final TextEditingController _capacityController;
  DateTime? _eventDate;
  TimeOfDay? _startTime;
  DateTime? _registrationClosesOn;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _titleController = TextEditingController(text: e?.title ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _locationController = TextEditingController(text: e?.locationText ?? '');
    _feeController = TextEditingController(
      text: e != null ? (e.feeCentavos ~/ 100).toString() : '',
    );
    _prizeController = TextEditingController(text: e?.prizeDescription ?? '');
    _capacityController = TextEditingController(
      text: e?.capacity?.toString() ?? '',
    );
    _eventDate = e?.eventDate;
    _registrationClosesOn = e?.registrationClosesOn;
    if (e?.startTime != null) {
      final parts = e!.startTime!.split(':');
      _startTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _feeController.dispose();
    _prizeController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickEventDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickRegistrationCloses() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _registrationClosesOn ?? _eventDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: _eventDate ?? DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _registrationClosesOn = picked);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    if (_eventDate == null) {
      setState(() => _error = 'Pick an event date.');
      return;
    }
    final feePesos = int.tryParse(_feeController.text.trim());
    if (feePesos == null || feePesos < 0) {
      setState(() => _error = 'Enter a valid fee (0 for free).');
      return;
    }
    final capacityText = _capacityController.text.trim();
    final capacity = capacityText.isEmpty ? null : int.tryParse(capacityText);
    if (capacityText.isNotEmpty && (capacity == null || capacity < 1)) {
      setState(() => _error = 'Capacity must be at least 1, or left blank for no limit.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(communityRepositoryProvider);
    final feeCentavos = feePesos * 100;
    try {
      if (_isEditing) {
        final startTimeValue = _startTime != null ? _fmtTime(_startTime!) : null;
        final closesValue = _registrationClosesOn != null ? _fmtDate(_registrationClosesOn!) : null;
        await repo.updateEvent(widget.event!.id, {
          'title': title,
          'description': _descriptionController.text.trim(),
          'event_date': _fmtDate(_eventDate!),
          'start_time': startTimeValue,
          'location_text': _locationController.text.trim(),
          'registration_fee': pesosToDecimalString(feeCentavos ~/ 100),
          'prize_description': _prizeController.text.trim(),
          'capacity': capacity,
          'registration_closes_on': closesValue,
        });
      } else {
        await repo.createEvent(
          title: title,
          description: _descriptionController.text.trim(),
          eventDate: _eventDate!,
          startTime: _startTime != null ? _fmtTime(_startTime!) : null,
          locationText: _locationController.text.trim(),
          feeCentavos: feeCentavos,
          prizeDescription: _prizeController.text.trim(),
          capacity: capacity,
          registrationClosesOn: _registrationClosesOn,
        );
      }
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

  Future<void> _cancelEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: const Text(
          'Registered members will see it marked cancelled. This does not '
          'delete anything or issue refunds.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cancel event')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(communityRepositoryProvider).cancelEvent(widget.event!.id);
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

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final isCanceled = widget.event?.isCanceled ?? false;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: Text(
          _isEditing ? 'Edit Event' : 'New Event',
          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Close', style: TextStyle(color: AppColors.muted)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _SectionHeader('BASIC DETAILS'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel('Title', required: true),
                  const SizedBox(height: 6),
                  _field(_titleController, hint: 'e.g. Annual Fun Cup & Bench Battle'),
                  const SizedBox(height: 14),
                  _fieldLabel('Description'),
                  const SizedBox(height: 6),
                  _field(_descriptionController, maxLines: 3,
                      hint: 'Describe the event rules, categories, format, and who can join...'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _SectionHeader('SCHEDULE & VENUE'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel('Event date', required: true),
                  const SizedBox(height: 6),
                  _dateTile(
                    _eventDate == null ? 'dd/mm/yyyy' : _fmtDate(_eventDate!),
                    _pickEventDate,
                    icon: Icons.calendar_today_outlined,
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Start time (optional)'),
                  const SizedBox(height: 6),
                  _dateTile(
                    _startTime == null ? '--:--' : _startTime!.format(context),
                    _pickStartTime,
                    icon: Icons.access_time,
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Location'),
                  const SizedBox(height: 6),
                  _field(_locationController, hint: 'e.g. Gym parking lot / Main lifting area',
                      icon: Icons.place_outlined),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _SectionHeader('REGISTRATION & PRIZES'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel('Registration fee (₱, 0 for free)'),
                  const SizedBox(height: 6),
                  _field(_feeController, keyboardType: TextInputType.number,
                      hint: '0 for free', icon: Icons.payments_outlined),
                  const SizedBox(height: 14),
                  _fieldLabel('Prize description (optional)'),
                  const SizedBox(height: 6),
                  _field(_prizeController, maxLines: 3,
                      hint: 'e.g. Trophy, ₱5,000 cash, 1-month VIP gym membership...'),
                  const SizedBox(height: 14),
                  _fieldLabel('Capacity (optional — blank for no limit)'),
                  const SizedBox(height: 6),
                  _field(_capacityController, keyboardType: TextInputType.number,
                      hint: 'e.g. 50 participants (or leave blank)', icon: Icons.groups_outlined),
                  const SizedBox(height: 14),
                  _fieldLabel('Registration closes (optional — defaults to event date)'),
                  const SizedBox(height: 6),
                  _dateTile(
                    _registrationClosesOn == null ? 'dd/mm/yyyy --:--' : _fmtDate(_registrationClosesOn!),
                    _pickRegistrationCloses,
                    icon: Icons.event_busy_outlined,
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.errorText)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox.shrink() : const Icon(Icons.add, size: 18),
                label: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? 'Save Changes' : 'Create Event'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
            if (_isEditing && !isCanceled) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _cancelEvent,
                  child: const Text('Cancel Event', style: TextStyle(color: AppColors.errorText)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) => Row(
    children: [
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.subtle)),
      if (required) const Text(' *', style: TextStyle(color: AppColors.errorText, fontSize: 12)),
    ],
  );

  Widget _field(TextEditingController controller,
      {String? hint, int maxLines = 1, TextInputType? keyboardType, IconData? icon}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.fieldBg, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Icon(icon, size: 17, color: AppColors.accentTeal),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
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
      ),
    );
  }

  Widget _dateTile(String text, VoidCallback onTap, {required IconData icon}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(color: AppColors.fieldBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.accentTeal),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.ink))),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 14, decoration: BoxDecoration(
          color: AppColors.accentTeal, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.subtle)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14)),
      child: child,
    );
  }
}