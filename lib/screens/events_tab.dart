import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/swimmer_events.dart';

/// The club's events and its active groups, for the coach screens.
class _EventsData {
  _EventsData(this.events, this.groups);
  final List<ClubEvent> events;
  final List<Group> groups;
}

/// The coach's Events tab: upcoming events (and recent past ones), with a
/// button to add a new one. Tap an event to change or delete it.
class EventsTab extends StatefulWidget {
  const EventsTab({super.key, required this.club});
  final Membership club;

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  bool _showPast = false;
  late Future<_EventsData> _data = _load();

  Future<_EventsData> _load() async {
    final today = dateOnly();
    final from = _showPast ? today.subtract(const Duration(days: 183)) : today;
    final results = await Future.wait([
      db
          .from('events')
          .select(eventColumns)
          .eq('club_id', widget.club.clubId)
          .gte('end_date', dbDate(from))
          .order('start_date')
          .order('start_time', nullsFirst: true),
      db
          .from('groups')
          .select()
          .eq('club_id', widget.club.clubId)
          .isFilter('archived_at', null),
    ]);
    return _EventsData([
      for (final r in results[0]) ClubEvent.fromRow(r),
    ], sortGroups([for (final r in results[1]) Group.fromRow(r)]));
  }

  void _refresh() => setState(() => _data = _load());

  Future<void> _openForm(List<Group> groups, [ClubEvent? event]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EventFormScreen(club: widget.club, groups: groups, event: event),
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  String _forWhom(ClubEvent e, List<Group> groups) {
    if (e.wholeClub) return 'Whole club';
    final names = [
      for (final g in groups)
        if (e.groupIds.contains(g.id)) g.name,
    ];
    return names.isEmpty ? 'Archived groups' : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EventsData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return LoadState(error: snapshot.error, onRetry: _refresh);
        }
        final today = dateOnly();
        final past = data.events.where((e) => e.endDate.isBefore(today));
        final upcoming = data.events.where((e) => !e.endDate.isBefore(today));
        final text = Theme.of(context).textTheme;
        Widget tile(ClubEvent e) => EventTile(
          event: e,
          extra: [
            'For: ${_forWhom(e, data.groups)}',
            if (e.cancelsTraining) 'Training cancelled',
          ].join('  ·  '),
          onTap: () => _openForm(data.groups, e),
        );
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _openForm(data.groups),
                    icon: const Icon(Icons.add),
                    label: const Text('New event'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Upcoming (${upcoming.length})',
                  style: text.titleMedium,
                ),
              ),
              if (upcoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'No upcoming events. Add a meet, a social or anything '
                    'else families should know about.',
                  ),
                ),
              for (final e in upcoming) tile(e),
              const Divider(height: 32),
              SwitchListTile(
                title: const Text('Show past events (last 6 months)'),
                value: _showPast,
                onChanged: (v) => setState(() {
                  _showPast = v;
                  _data = _load();
                }),
              ),
              for (final e in past.toList().reversed) tile(e),
            ],
          ),
        );
      },
    );
  }
}

/// Adds a new event, or changes or deletes [event].
/// Pops with true when something was saved or deleted.
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({
    super.key,
    required this.club,
    required this.groups,
    this.event,
  });
  final Membership club;
  final List<Group> groups;
  final ClubEvent? event;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late final ClubEvent? _old = widget.event;
  late final _title = TextEditingController(text: _old?.title);
  late final _venue = TextEditingController(text: _old?.venue);
  late final _notes = TextEditingController(text: _old?.notes);
  late final _link = TextEditingController(text: _old?.link);
  late String _kind = _old?.kind ?? 'meet';
  late String? _course = _old?.course;
  late DateTime _startDate = _old?.startDate ?? dateOnly();
  late DateTime _endDate = _old?.endDate ?? dateOnly();
  late bool _allDay = _old == null ? false : _old.allDay;
  late int _start = _old?.start ?? 7 * 60;
  late int _end = _old?.end ?? 17 * 60;
  late bool _wholeClub = _old?.wholeClub ?? true;
  late final Set<String> _groupIds = {...?_old?.groupIds};
  late bool _cancelTraining = _old?.cancelsTraining ?? false;
  bool _notify = true;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _venue.dispose();
    _notes.dispose();
    _link.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<DateTime?> _pickDate(String help, DateTime current, DateTime first) {
    return showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: dateOnly().add(const Duration(days: 730)),
      helpText: help,
    );
  }

  Future<int?> _pickTime(String help, int current) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: help,
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  /// The earliest day the date pickers allow: today, or the event's own
  /// first day when changing a past event.
  DateTime get _firstAllowed {
    final today = dateOnly();
    final old = _old?.startDate;
    return old != null && old.isBefore(today) ? old : today;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    String? problem;
    if (_clean(_title) == null) {
      problem = 'Give the event a title.';
    } else if (!_wholeClub && _groupIds.isEmpty) {
      problem = 'Pick at least one group, or Whole club.';
    } else if (!_allDay && _startDate == _endDate && _end <= _start) {
      problem = 'The end time must be after the start time.';
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
        'save_event',
        params: {
          'p_event_id': _old?.id,
          'p_club_id': widget.club.clubId,
          'p_title': _clean(_title),
          'p_kind': _kind,
          'p_start_date': dbDate(_startDate),
          'p_end_date': dbDate(_endDate),
          'p_start_time': _allDay ? null : dbTime(_start),
          'p_end_time': _allDay ? null : dbTime(_end),
          'p_venue': _clean(_venue),
          'p_course': _kind == 'meet' ? _course : null,
          'p_notes': _clean(_notes),
          'p_link': _clean(_link),
          'p_group_ids': _wholeClub ? <String>[] : _groupIds.toList(),
          'p_cancel_training': _cancelTraining,
          'p_notify': _notify,
        },
      ),
      done: _old == null ? 'Event added.' : 'Event saved.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final e = _old!;
    final yes = await confirm(
      context,
      title: 'Delete ${e.title}?',
      message: e.cancelsTraining
          ? 'Families will no longer see it, and the training it '
                'cancelled comes back.'
          : 'Families will no longer see it.',
      yes: 'Delete',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(
      context,
      () => db.rpc('delete_event', params: {'p_event_id': e.id}),
      done: 'Event deleted.',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: Text(_old == null ? 'New event' : 'Edit event'),
        actions: [
          if (_old != null)
            IconButton(
              tooltip: 'Delete event',
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
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Dec Age Group Champs',
            ),
          ),
          gap,
          SegmentedButton<String>(
            segments: [
              for (final k in eventKinds)
                ButtonSegment(value: k, label: Text(eventKindLabel(k))),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          gap,
          Text('When', style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('First day  ${formatDate(_startDate)}'),
                onPressed: () async {
                  final d = await _pickDate(
                    'First day',
                    _startDate,
                    _firstAllowed,
                  );
                  if (d == null) return;
                  setState(() {
                    // Keep the same length when the first day moves.
                    final length = _endDate.difference(_startDate);
                    _startDate = dateOnly(d);
                    _endDate = _startDate.add(length);
                  });
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('Last day  ${formatDate(_endDate)}'),
                onPressed: () async {
                  final d = await _pickDate('Last day', _endDate, _startDate);
                  if (d != null) setState(() => _endDate = dateOnly(d));
                },
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          if (!_allDay)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('Starts  ${formatTime(_start)}'),
                  onPressed: () async {
                    final m = await _pickTime('Starts', _start);
                    if (m != null) setState(() => _start = m);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('Ends  ${formatTime(_end)}'),
                  onPressed: () async {
                    final m = await _pickTime('Ends', _end);
                    if (m != null) setState(() => _end = m);
                  },
                ),
              ],
            ),
          gap,
          TextField(
            controller: _venue,
            decoration: const InputDecoration(
              labelText: 'Place (optional)',
              hintText: 'e.g. Rizal Memorial Pool',
            ),
          ),
          if (_kind == 'meet') ...[
            gap,
            Text('Pool course', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(value: 'lcm', label: Text('LCM (50 m)')),
                ButtonSegment(value: 'scm', label: Text('SCM (25 m)')),
              ],
              selected: {?_course},
              onSelectionChanged: (s) =>
                  setState(() => _course = s.isEmpty ? null : s.first),
            ),
          ],
          gap,
          Text('Who is it for?', style: text.titleSmall),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Whole club'),
            value: _wholeClub,
            onChanged: (v) => setState(() => _wholeClub = v ?? true),
          ),
          if (!_wholeClub)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final g in widget.groups)
                  FilterChip(
                    label: Text(g.name),
                    selected: _groupIds.contains(g.id),
                    onSelected: (on) => setState(
                      () => on ? _groupIds.add(g.id) : _groupIds.remove(g.id),
                    ),
                  ),
              ],
            ),
          gap,
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. Warm-up 6:15 AM. Bring club cap and shirt.',
            ),
          ),
          gap,
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Web link (optional)',
              hintText: 'Meet information page',
            ),
          ),
          gap,
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cancel training these days'),
            subtitle: Text(
              _wholeClub
                  ? 'Turns these days into rest days for the whole club.'
                  : 'Turns these days into rest days for the groups above.',
            ),
            value: _cancelTraining,
            onChanged: (v) => setState(() => _cancelTraining = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _old == null
                  ? 'Notify families'
                  : 'Notify families of the change',
            ),
            subtitle: const Text(
              'Push notifications are switched on in a later update.',
            ),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v ?? true),
          ),
        ],
      ),
    );
  }
}
