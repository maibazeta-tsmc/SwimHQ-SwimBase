import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';

// The small forms used on a group's Schedule tab. Each returns what the
// coach filled in, or null if they tapped Cancel.

/// A time button that opens the clock picker. [minutes] is after midnight.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          helpText: label,
        );
        if (picked != null) onChanged(picked.hour * 60 + picked.minute);
      },
      child: Text('$label  ${formatTime(minutes)}'),
    );
  }
}

/// A date button that opens the calendar picker.
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.onChanged,
    required this.first,
  });
  final String label;
  final DateTime date;
  final DateTime first;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 18),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date.isBefore(first) ? first : date,
          firstDate: first,
          lastDate: first.add(const Duration(days: 365)),
          helpText: label,
        );
        if (picked != null) onChanged(dateOnly(picked));
      },
      label: Text('$label  ${formatDate(date)}'),
    );
  }
}

String? _clean(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : t;
}

// ---------- Weekly session ----------

class WeeklyForm {
  WeeklyForm(
    this.weekdays,
    this.start,
    this.end,
    this.label,
    this.venue,
    this.startsOn,
  );
  final Set<int> weekdays;
  final int start;
  final int end;
  final String? label;
  final String? venue;
  final DateTime startsOn;
}

Future<WeeklyForm?> showWeeklyForm(BuildContext context) =>
    showDialog<WeeklyForm>(context: context, builder: (_) => const _Weekly());

class _Weekly extends StatefulWidget {
  const _Weekly();
  @override
  State<_Weekly> createState() => _WeeklyState();
}

class _WeeklyState extends State<_Weekly> {
  final Set<int> _days = {};
  int _start = 16 * 60 + 30;
  int _end = 19 * 60;
  DateTime _from = dateOnly();
  final _label = TextEditingController();
  final _venue = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _venue.dispose();
    super.dispose();
  }

  void _save() {
    if (_days.isEmpty) {
      setState(() => _error = 'Tick at least one day.');
    } else if (_end <= _start) {
      setState(() => _error = 'The end time must be after the start time.');
    } else {
      Navigator.pop(
        context,
        WeeklyForm(_days, _start, _end, _clean(_label), _clean(_venue), _from),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add weekly session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Which days?'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(weekdayShort(d)),
                    selected: _days.contains(d),
                    onSelected: (on) =>
                        setState(() => on ? _days.add(d) : _days.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TimeButton(
                  label: 'From',
                  minutes: _start,
                  onChanged: (m) => setState(() => _start = m),
                ),
                _TimeButton(
                  label: 'To',
                  minutes: _end,
                  onChanged: (m) => setState(() => _end = m),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DateButton(
              label: 'Starts',
              date: _from,
              first: dateOnly(),
              onChanged: (d) => setState(() => _from = d),
            ),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'e.g. AM, Dryland',
              ),
            ),
            TextField(
              controller: _venue,
              decoration: const InputDecoration(labelText: 'Pool (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }
}

// ---------- One-off session ----------

class OneOffForm {
  OneOffForm(
    this.groupIds,
    this.date,
    this.start,
    this.end,
    this.label,
    this.venue,
  );
  final List<String> groupIds;
  final DateTime date;
  final int start;
  final int end;
  final String? label;
  final String? venue;
}

/// [groups] are the groups the coach may add to; [groupId] starts ticked.
Future<OneOffForm?> showOneOffForm(
  BuildContext context, {
  required String groupId,
  required List<Group> groups,
}) => showDialog<OneOffForm>(
  context: context,
  builder: (_) => _OneOff(groupId: groupId, groups: groups),
);

class _OneOff extends StatefulWidget {
  const _OneOff({required this.groupId, required this.groups});
  final String groupId;
  final List<Group> groups;
  @override
  State<_OneOff> createState() => _OneOffState();
}

class _OneOffState extends State<_OneOff> {
  late final Set<String> _groups = {widget.groupId};
  DateTime _date = dateOnly();
  int _start = 7 * 60;
  int _end = 9 * 60;
  final _label = TextEditingController();
  final _venue = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _venue.dispose();
    super.dispose();
  }

  void _save() {
    if (_groups.isEmpty) {
      setState(() => _error = 'Tick at least one group.');
    } else if (_end <= _start) {
      setState(() => _error = 'The end time must be after the start time.');
    } else {
      Navigator.pop(
        context,
        OneOffForm(
          _groups.toList(),
          _date,
          _start,
          _end,
          _clean(_label),
          _clean(_venue),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add one-off session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateButton(
              label: 'Date',
              date: _date,
              first: dateOnly(),
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TimeButton(
                  label: 'From',
                  minutes: _start,
                  onChanged: (m) => setState(() => _start = m),
                ),
                _TimeButton(
                  label: 'To',
                  minutes: _end,
                  onChanged: (m) => setState(() => _end = m),
                ),
              ],
            ),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'e.g. Time trial',
              ),
            ),
            TextField(
              controller: _venue,
              decoration: const InputDecoration(labelText: 'Pool (optional)'),
            ),
            if (widget.groups.length > 1) ...[
              const SizedBox(height: 12),
              const Text('For which groups?'),
              for (final g in widget.groups)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _groups.contains(g.id),
                  title: Text(g.name),
                  onChanged: (v) => setState(
                    () => v == true ? _groups.add(g.id) : _groups.remove(g.id),
                  ),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }
}

// ---------- Rest days ----------

class RestForm {
  RestForm(this.start, this.end, this.isBreak, this.title, this.wholeClub);
  final DateTime start;
  final DateTime end;
  final bool isBreak;
  final String? title;
  final bool wholeClub;
}

/// [canDoWholeClub] shows the "Whole club" choice (head coach).
Future<RestForm?> showRestForm(
  BuildContext context, {
  required String groupName,
  required bool canDoWholeClub,
}) => showDialog<RestForm>(
  context: context,
  builder: (_) => _Rest(groupName: groupName, canDoWholeClub: canDoWholeClub),
);

class _Rest extends StatefulWidget {
  const _Rest({required this.groupName, required this.canDoWholeClub});
  final String groupName;
  final bool canDoWholeClub;
  @override
  State<_Rest> createState() => _RestState();
}

class _RestState extends State<_Rest> {
  DateTime _start = dateOnly();
  DateTime _end = dateOnly();
  bool _isBreak = false;
  bool _wholeClub = false;
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add rest days'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Rest day')),
                ButtonSegment(value: true, label: Text('Break')),
              ],
              selected: {_isBreak},
              onSelectionChanged: (s) => setState(() => _isBreak = s.first),
            ),
            const SizedBox(height: 12),
            _DateButton(
              label: 'First day',
              date: _start,
              first: dateOnly(),
              onChanged: (d) => setState(() {
                _start = d;
                if (_end.isBefore(d)) _end = d;
              }),
            ),
            const SizedBox(height: 8),
            _DateButton(
              label: 'Last day',
              date: _end,
              first: _start,
              onChanged: (d) => setState(() => _end = d),
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'e.g. Christmas break',
              ),
            ),
            if (widget.canDoWholeClub) ...[
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(widget.groupName)),
                  const ButtonSegment(value: true, label: Text('Whole club')),
                ],
                selected: {_wholeClub},
                onSelectionChanged: (s) => setState(() => _wholeClub = s.first),
              ),
            ],
            const SizedBox(height: 8),
            const Text('Sessions on these days will be cancelled.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RestForm(_start, _end, _isBreak, _clean(_title), _wholeClub),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ---------- Change one session's time ----------

class TimeChange {
  TimeChange(this.start, this.end);
  final int start;
  final int end;
}

Future<TimeChange?> showTimeChangeForm(
  BuildContext context,
  TrainingSession session,
) => showDialog<TimeChange>(
  context: context,
  builder: (_) => _TimeChangeDialog(session: session),
);

class _TimeChangeDialog extends StatefulWidget {
  const _TimeChangeDialog({required this.session});
  final TrainingSession session;
  @override
  State<_TimeChangeDialog> createState() => _TimeChangeDialogState();
}

class _TimeChangeDialogState extends State<_TimeChangeDialog> {
  late int _start = widget.session.start;
  late int _end = widget.session.end;

  @override
  Widget build(BuildContext context) {
    final bad = _end <= _start;
    return AlertDialog(
      title: Text('Change time on ${formatDayShort(widget.session.date)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Only this day changes. The weekly schedule stays.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TimeButton(
                label: 'From',
                minutes: _start,
                onChanged: (m) => setState(() => _start = m),
              ),
              _TimeButton(
                label: 'To',
                minutes: _end,
                onChanged: (m) => setState(() => _end = m),
              ),
            ],
          ),
          if (bad)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The end time must be after the start time.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: bad
              ? null
              : () => Navigator.pop(context, TimeChange(_start, _end)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Asks for an optional reason before cancelling. Returns null if the coach
/// changed their mind, or the reason ('' for none).
Future<String?> askCancelReason(BuildContext context, String what) {
  final reason = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Cancel $what?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Families will see it as cancelled.'),
          TextField(
            controller: reason,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'e.g. Pool maintenance',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, reason.text.trim()),
          child: const Text('Cancel session'),
        ),
      ],
    ),
  );
}
