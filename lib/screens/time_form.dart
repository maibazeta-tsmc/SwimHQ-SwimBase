import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Opens the form to add a time (or change or delete [result]).
/// [swimmers] are the swimmers the coach can pick from; when there is
/// only one, the swimmer is fixed. Returns true when something changed.
Future<bool> openTimeForm(
  BuildContext context, {
  required Membership club,
  required List<Swimmer> swimmers,
  SwimResult? result,
  String? course,
  SwimEvent? event,
}) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => TimeFormScreen(
        club: club,
        swimmers: swimmers,
        result: result,
        course: course,
        event: event,
      ),
    ),
  );
  return changed == true;
}

/// Adds a swim time by hand, or changes or deletes one. Shows the
/// swimmer's current PB in that event and how far the new time is off it.
class TimeFormScreen extends StatefulWidget {
  const TimeFormScreen({
    super.key,
    required this.club,
    required this.swimmers,
    this.result,
    this.course,
    this.event,
  });
  final Membership club;
  final List<Swimmer> swimmers;
  final SwimResult? result;
  final String? course;
  final SwimEvent? event;

  @override
  State<TimeFormScreen> createState() => _TimeFormScreenState();
}

/// A meet the coach can pick: a name, with its day and course when it
/// comes from the club's Events.
class _MeetOption {
  _MeetOption(this.name, {this.eventId, this.date, this.course});
  final String name;
  final String? eventId;
  final DateTime? date;
  final String? course;
}

class _TimeFormScreenState extends State<TimeFormScreen> {
  late final SwimResult? _old = widget.result;
  late String? _swimmerId =
      _old?.swimmerId ??
      (widget.swimmers.length == 1 ? widget.swimmers.first.id : null);
  late String _course = _old?.course ?? widget.course ?? 'lcm';
  late SwimEvent? _event = _old?.event ?? widget.event;
  late final _time = TextEditingController(
    text: _old == null ? '' : formatSwimTime(_old.timeCs),
  );
  late final _meet = TextEditingController(text: _old?.meetName);
  late DateTime _date = _old?.date ?? dateOnly();
  late String? _eventId = _old?.eventId;
  bool _saving = false;

  /// The chosen swimmer's times, for the current PB line.
  Future<List<SwimResult>>? _swims;
  late final Future<List<_MeetOption>> _meets = _loadMeets();

  @override
  void initState() {
    super.initState();
    _loadSwims();
    _time.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _time.dispose();
    _meet.dispose();
    super.dispose();
  }

  void _loadSwims() {
    final id = _swimmerId;
    // ignore() keeps a failed load quiet until the PB line shows it.
    _swims = id == null ? null : (_fetchSwims(id)..ignore());
  }

  Future<List<SwimResult>> _fetchSwims(String swimmerId) async {
    final rows = await db
        .from('swim_results')
        .select(swimResultColumns)
        .eq('swimmer_id', swimmerId);
    return [for (final r in rows) SwimResult.fromRow(r)];
  }

  /// Meets from Events (last year up to today) and meet names already
  /// used for times, newest first, for the meet suggestions.
  Future<List<_MeetOption>> _loadMeets() async {
    final today = dateOnly();
    final results = await Future.wait([
      db
          .from('events')
          .select('id, title, start_date, course')
          .eq('club_id', widget.club.clubId)
          .eq('kind', 'meet')
          .lte('start_date', dbDate(today))
          .gte('start_date', dbDate(today.subtract(const Duration(days: 366))))
          .order('start_date', ascending: false),
      db
          .from('swim_results')
          .select('meet_name, swim_date')
          .eq('club_id', widget.club.clubId)
          .order('created_at', ascending: false)
          .limit(300),
    ]);
    final options = <_MeetOption>[
      for (final e in results[0])
        _MeetOption(
          e['title'] as String,
          eventId: e['id'] as String,
          date: DateTime.parse(e['start_date'] as String),
          course: e['course'] as String?,
        ),
    ];
    final seen = {for (final o in options) o.name.toLowerCase()};
    for (final r in results[1]) {
      final name = r['meet_name'] as String;
      if (seen.add(name.toLowerCase())) options.add(_MeetOption(name));
    }
    return options;
  }

  Swimmer? get _swimmer {
    for (final s in widget.swimmers) {
      if (s.id == _swimmerId) return s;
    }
    return null;
  }

  void _pickMeet(_MeetOption m) {
    setState(() {
      _meet.text = m.name;
      _eventId = m.eventId;
      if (m.date != null) _date = m.date!;
      if (m.course != null) _course = m.course!;
      if (_event != null && !swimEvents(_course).contains(_event)) {
        _event = null;
      }
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final cs = parseSwimTime(_time.text);
    String? problem;
    if (_swimmerId == null) {
      problem = 'Pick the swimmer.';
    } else if (_event == null) {
      problem = 'Pick the event.';
    } else if (cs == null) {
      problem = 'Type the time like 1:05.42 or 29.84.';
    } else if (_meet.text.trim().isEmpty) {
      problem = 'Type the meet name.';
    }
    if (problem != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => db.rpc(
        'save_swim_result',
        params: {
          'p_result_id': _old?.id,
          'p_swimmer_id': _swimmerId,
          'p_course': _course,
          'p_stroke': _event!.stroke,
          'p_distance': _event!.distance,
          'p_time_cs': cs,
          'p_meet_name': _meet.text.trim(),
          'p_swim_date': dbDate(_date),
          'p_event_id': _eventId,
        },
      ),
      done: _old == null
          ? 'Time added: ${_event!.label} ${formatSwimTime(cs!)}.'
          : 'Time saved.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final r = _old!;
    final yes = await confirm(
      context,
      title: 'Delete this time?',
      message:
          '${r.event.label} ${formatSwimTime(r.timeCs)} at ${r.meetName} '
          'will be removed. If it was a PB, the next fastest time becomes '
          'the PB.',
      yes: 'Delete',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(
      context,
      () => db.rpc('delete_swim_result', params: {'p_result_id': r.id}),
      done: 'Time deleted.',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  /// "Current PB 1:06.10 (Oct 2026)" and "New PB -0.68" lines.
  Widget _pbLine(BuildContext context) {
    final event = _event;
    final swims = _swims;
    if (event == null || swims == null) return const SizedBox.shrink();
    return FutureBuilder<List<SwimResult>>(
      future: swims,
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) return const SizedBox.shrink();
        // Leave out the time being edited, to compare with the others.
        final others = swimsIn(
          all.where((r) => r.id != _old?.id),
          _course,
          event,
        );
        final text = Theme.of(context).textTheme;
        final cs = parseSwimTime(_time.text);
        if (others.isEmpty) {
          return Text(
            cs == null
                ? 'No ${event.label} ${_course.toUpperCase()} time yet.'
                : 'First ${event.label} ${_course.toUpperCase()} time: '
                      'this will be the PB.',
            style: text.bodyMedium,
          );
        }
        final pb = others.first;
        final lines = [
          'Current PB  ${formatSwimTime(pb.timeCs)}  '
              '(${pb.meetName}, ${formatDate(pb.date)})',
        ];
        if (cs != null) {
          final diff = cs - pb.timeCs;
          lines.add(
            diff < 0
                ? 'New PB  ${formatTimeDiff(diff)}'
                : 'Not a PB  ${formatTimeDiff(diff)}',
          );
        }
        return Text(lines.join('\n'), style: text.bodyMedium);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    const compact = VisualDensity(horizontal: -2, vertical: -3);
    final swimmer = _swimmer;
    final fixedSwimmer = _old != null || widget.swimmers.length == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(_old == null ? 'Add a time' : 'Edit time'),
        actions: [
          if (_old != null)
            IconButton(
              tooltip: 'Delete time',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (fixedSwimmer)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(swimmer?.fullName ?? 'Swimmer'),
            )
          else
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              label: const Text('Swimmer'),
              enableFilter: true,
              requestFocusOnTap: true,
              initialSelection: _swimmerId,
              dropdownMenuEntries: [
                for (final s in widget.swimmers)
                  DropdownMenuEntry(value: s.id, label: s.fullName),
              ],
              onSelected: (id) => setState(() {
                _swimmerId = id;
                _loadSwims();
              }),
            ),
          gap,
          SegmentedButton<String>(
            style: const ButtonStyle(visualDensity: compact),
            showSelectedIcon: false,
            segments: [
              for (final c in courses)
                ButtonSegment(value: c, label: Text(courseShort(c))),
            ],
            selected: {_course},
            onSelectionChanged: (s) => setState(() {
              _course = s.first;
              if (_event != null && !swimEvents(_course).contains(_event)) {
                _event = null;
              }
            }),
          ),
          gap,
          DropdownMenu<SwimEvent>(
            // Rebuilt when the course changes, so the list is right.
            key: ValueKey('event-$_course-$_event'),
            expandedInsets: EdgeInsets.zero,
            label: const Text('Event'),
            initialSelection: _event,
            dropdownMenuEntries: [
              for (final e in swimEvents(_course))
                DropdownMenuEntry(value: e, label: e.label),
            ],
            onSelected: (e) => setState(() => _event = e),
          ),
          gap,
          TextField(
            controller: _time,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Time',
              hintText: 'e.g. 1:05.42 or 29.84',
              errorText:
                  _time.text.trim().isNotEmpty &&
                      parseSwimTime(_time.text) == null
                  ? 'Type minutes:seconds.hundredths, like 1:05.42'
                  : null,
            ),
          ),
          gap,
          FutureBuilder<List<_MeetOption>>(
            future: _meets,
            builder: (context, snapshot) {
              final options = snapshot.data ?? const <_MeetOption>[];
              return Autocomplete<_MeetOption>(
                initialValue: TextEditingValue(text: _meet.text),
                displayStringForOption: (o) => o.name,
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  return options
                      .where(
                        (o) => q.isEmpty || o.name.toLowerCase().contains(q),
                      )
                      .take(8);
                },
                onSelected: _pickMeet,
                optionsViewBuilder: (context, onSelected, list) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 280,
                        maxWidth: 420,
                      ),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final o in list)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                o.eventId == null ? Icons.history : Icons.event,
                              ),
                              title: Text(o.name),
                              subtitle: o.date == null
                                  ? null
                                  : Text(
                                      [
                                        formatDate(o.date!),
                                        if (o.course != null)
                                          o.course!.toUpperCase(),
                                      ].join('  ·  '),
                                    ),
                              onTap: () => onSelected(o),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                fieldViewBuilder: (context, controller, focus, onSubmit) =>
                    TextField(
                      controller: controller,
                      focusNode: focus,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Meet',
                        hintText: 'e.g. Club time trial',
                      ),
                      onChanged: (v) {
                        _meet.text = v;
                        // A typed name is no longer the picked Events meet.
                        if (_eventId != null) setState(() => _eventId = null);
                      },
                    ),
              );
            },
          ),
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Date  ${formatDate(_date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: swimmer?.birthDate ?? DateTime(2000),
                  lastDate: dateOnly(),
                  helpText: 'Date of the swim',
                );
                if (d != null) setState(() => _date = dateOnly(d));
              },
            ),
          ),
          const Divider(height: 32),
          _pbLine(context),
        ],
      ),
    );
  }
}
