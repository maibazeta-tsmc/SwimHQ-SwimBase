import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../widgets/common.dart';

/// What the coach typed into the group form.
class GroupFormResult {
  GroupFormResult(this.name, this.level, this.colour, this.description);
  final String name;
  final int level;
  final String? colour;
  final String? description;

  Map<String, dynamic> toRow() => {
    'name': name,
    'level': level,
    'colour': colour,
    'description': description,
  };
}

/// Opens the "New group" / "Edit group" form. Returns null if cancelled.
Future<GroupFormResult?> showGroupForm(
  BuildContext context, {
  Group? group,
  int suggestedLevel = 1,
}) {
  return showDialog<GroupFormResult>(
    context: context,
    builder: (_) => _GroupForm(group: group, suggestedLevel: suggestedLevel),
  );
}

class _GroupForm extends StatefulWidget {
  const _GroupForm({this.group, required this.suggestedLevel});
  final Group? group;
  final int suggestedLevel;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final _level = TextEditingController(
    text: '${widget.group?.level ?? widget.suggestedLevel}',
  );
  late final _description = TextEditingController(
    text: widget.group?.description ?? '',
  );
  late String? _colour = widget.group?.colour;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _level.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final level = int.tryParse(_level.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    if (level == null || level < 1) {
      setState(() => _error = 'The level must be a whole number, 1 or more.');
      return;
    }
    final description = _description.text.trim();
    Navigator.pop(
      context,
      GroupFormResult(
        name,
        level,
        _colour,
        description.isEmpty ? null : description,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group == null ? 'New group' : 'Edit group'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.group == null,
              decoration: const InputDecoration(labelText: 'Name, e.g. Gold'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _level,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Level',
                helperText:
                    '1 = entry level. Higher number = higher group.\n'
                    'Two groups can share a level.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Colour (optional)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in groupColours.entries)
                  Tooltip(
                    message: entry.key,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(
                        () => _colour = _colour == entry.key ? null : entry.key,
                      ),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: entry.value,
                        child: _colour == entry.key
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
