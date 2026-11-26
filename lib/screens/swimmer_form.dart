import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';

/// What the coach typed into the swimmer form.
class SwimmerFormResult {
  SwimmerFormResult(
    this.firstName,
    this.lastName,
    this.birthDate,
    this.gender,
    this.groupId,
  );
  final String firstName;
  final String lastName;
  final DateTime birthDate;
  final String gender;

  /// Only used when adding a swimmer (their first group).
  final String? groupId;
}

/// Opens the "Add swimmer" form, or "Edit details" when [swimmer] is given.
/// [groups] are the groups a new swimmer can start in.
Future<SwimmerFormResult?> showSwimmerForm(
  BuildContext context, {
  Swimmer? swimmer,
  List<Group> groups = const [],
  String? startGroupId,
}) {
  return showDialog<SwimmerFormResult>(
    context: context,
    builder: (_) => _SwimmerForm(
      swimmer: swimmer,
      groups: groups,
      startGroupId: startGroupId,
    ),
  );
}

class _SwimmerForm extends StatefulWidget {
  const _SwimmerForm({
    this.swimmer,
    required this.groups,
    required this.startGroupId,
  });
  final Swimmer? swimmer;
  final List<Group> groups;
  final String? startGroupId;

  @override
  State<_SwimmerForm> createState() => _SwimmerFormState();
}

class _SwimmerFormState extends State<_SwimmerForm> {
  late final _first = TextEditingController(
    text: widget.swimmer?.firstName ?? '',
  );
  late final _last = TextEditingController(
    text: widget.swimmer?.lastName ?? '',
  );
  late DateTime? _birth = widget.swimmer?.birthDate;
  late String? _gender = widget.swimmer?.gender;
  late String? _groupId = widget.startGroupId;
  String? _error;

  bool get _adding => widget.swimmer == null;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 10, 1, 1),
      firstDate: DateTime(now.year - 80),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _birth = picked);
  }

  void _save() {
    final first = _first.text.trim();
    final last = _last.text.trim();
    String? problem;
    if (first.isEmpty || last.isEmpty) {
      problem = 'Enter a first and last name.';
    } else if (_birth == null) {
      problem = 'Choose the date of birth.';
    } else if (_gender == null) {
      problem = 'Choose male or female (used for Team Records).';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(
      context,
      SwimmerFormResult(first, last, _birth!, _gender!, _groupId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_adding ? 'Add a swimmer' : 'Edit details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _first,
              autofocus: _adding,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _last,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickBirthDate,
              icon: const Icon(Icons.cake_outlined),
              label: Text(
                _birth == null
                    ? 'Date of birth'
                    : '${formatDate(_birth!)}  (age ${ageOn(_birth!)})',
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(value: 'male', label: Text('Male')),
                ButtonSegment(value: 'female', label: Text('Female')),
              ],
              selected: {?_gender},
              onSelectionChanged: (s) =>
                  setState(() => _gender = s.isEmpty ? null : s.first),
            ),
            if (_adding) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: 'First group'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No group yet (Unassigned)'),
                  ),
                  for (final g in widget.groups)
                    DropdownMenuItem(
                      value: g.id,
                      child: Text('${g.name} (level ${g.level})'),
                    ),
                ],
                onChanged: (v) => setState(() => _groupId = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_adding ? 'Add swimmer' : 'Save'),
        ),
      ],
    );
  }
}
