import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';

/// One swimmer's mark while the coach is editing it.
class _Mark {
  _Mark(this.status, this.reason, this.note);
  String status;
  String? reason; // only for Excused
  String? note; // coaches only
}

/// Take attendance for one session. Everyone starts as Present, so the
/// coach only taps the exceptions and then Save.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.club,
    required this.session,
  });
  final Membership club;
  final SessionOverview session;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late Future<List<RosterEntry>> _roster = _load();
  final Map<String, _Mark> _marks = {};
  bool _changed = false;
  bool _saving = false;

  Future<List<RosterEntry>> _load() async {
    final rows = await db.rpc(
      'session_roster',
      params: {'p_session_id': widget.session.sessionId},
    );
    final roster = [for (final r in rows as List) RosterEntry.fromRow(r)];
    _marks
      ..clear()
      ..addAll({
        for (final e in roster)
          e.swimmerId: _Mark(e.status ?? 'present', e.excuseReason, e.note),
      });
    _changed = false;
    return roster;
  }

  void _reload() => setState(() => _roster = _load());

  bool get _canEdit =>
      widget.club.isCoach &&
      !widget.session.cancelled &&
      canMarkAttendance(
        widget.session.date,
        isHeadCoach: widget.club.isHeadCoach,
      );

  void _set(String swimmerId, String status) => setState(() {
    final m = _marks[swimmerId]!;
    m.status = status;
    if (status != 'excused') m.reason = null;
    _changed = true;
  });

  void _allPresent() => setState(() {
    for (final m in _marks.values) {
      m.status = 'present';
      m.reason = null;
    }
    _changed = true;
  });

  Future<void> _editNote(RosterEntry e) async {
    final m = _marks[e.swimmerId]!;
    final controller = TextEditingController(text: m.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Note for ${e.firstName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'e.g. fever, left early for a test',
            helperText: 'Only coaches see notes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (note == null) return;
    setState(() {
      m.note = note.isEmpty ? null : note;
      _changed = true;
    });
  }

  Future<void> _save(List<RosterEntry> roster) async {
    final missing = [
      for (final e in roster)
        if (_marks[e.swimmerId]!.status == 'excused' &&
            _marks[e.swimmerId]!.reason == null)
          e.firstName,
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pick Medical, School or Family for ${missing.join(', ')}.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      () => db.rpc(
        'save_attendance',
        params: {
          'p_session_id': widget.session.sessionId,
          'p_marks': [
            for (final e in roster)
              {
                'swimmer_id': e.swimmerId,
                'status': _marks[e.swimmerId]!.status,
                'excuse_reason': _marks[e.swimmerId]!.reason,
                'note': _marks[e.swimmerId]!.note,
              },
          ],
        },
      ),
      done: 'Attendance saved.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) navigator.pop(true);
  }

  Future<void> _clear() async {
    final yes = await confirm(
      context,
      title: 'Clear this attendance?',
      message:
          'Every mark for this session is removed, and families no '
          'longer see it. Do this if attendance was taken by mistake or '
          'before cancelling the session.',
      yes: 'Clear',
    );
    if (!yes || !mounted) return;
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      () => db.rpc(
        'clear_attendance',
        params: {'p_session_id': widget.session.sessionId},
      ),
      done: 'Attendance cleared.',
    );
    if (ok) navigator.pop(true);
  }

  Future<bool> _confirmLeave() async {
    if (!_changed || !_canEdit) return true;
    return confirm(
      context,
      title: 'Leave without saving?',
      message: 'The marks you changed are not saved yet.',
      yes: 'Leave',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return PopScope(
      canPop: !_changed || !_canEdit,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          _changed = false;
          navigator.pop();
        }
      },
      child: FutureBuilder<List<RosterEntry>>(
        future: _roster,
        builder: (context, snapshot) {
          final roster = snapshot.data;
          return Scaffold(
            appBar: AppBar(
              title: Text('${s.groupName}  ·  ${formatDayShort(s.date)}'),
              actions: [
                if (_canEdit && s.isMarked)
                  PopupMenuButton<String>(
                    onSelected: (_) => _clear(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'clear',
                        child: Text('Clear attendance'),
                      ),
                    ],
                  ),
              ],
            ),
            bottomNavigationBar: roster == null || roster.isEmpty || !_canEdit
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: _saving ? null : () => _save(roster),
                        icon: const Icon(Icons.check),
                        label: Text(_saving ? 'Saving...' : 'Save'),
                      ),
                    ),
                  ),
            body: roster == null
                ? LoadState(error: snapshot.error, onRetry: _reload)
                : _body(roster),
          );
        },
      ),
    );
  }

  Widget _body(List<RosterEntry> roster) {
    final s = widget.session;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final summary = AttendanceSummary(
      roster.map((e) => _marks[e.swimmerId]!.status),
    );
    RosterEntry? last;
    for (final e in roster) {
      if (e.markedAt != null &&
          (last == null || e.markedAt!.isAfter(last.markedAt!))) {
        last = e;
      }
    }
    final notice = s.cancelled
        ? 'This session was cancelled, so it has no attendance.'
        : !widget.club.isCoach
        ? 'Read only.'
        : s.date.isAfter(dateOnly())
        ? 'This session hasn\'t happened yet. Take attendance on the day.'
        : !_canEdit
        ? 'This session was more than 7 days ago. Only the head coach can '
              'change it now.'
        : null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            [
              timeRange(s.start, s.end),
              if (s.label != null) s.label!,
              if (s.venue != null) s.venue!,
            ].join('  ·  '),
            style: text.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '${roster.length} swimmers   '
            '${[for (final st in attendanceStatuses)
              if (summary.count(st) > 0) '${attendanceLetter(st)} ${summary.count(st)}'].join('  ')}',
          ),
        ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Updated by ${last.markedBy ?? 'a coach'} '
              'on ${formatDayShort(last.markedAt!)} at '
              '${formatTime(last.markedAt!.hour * 60 + last.markedAt!.minute)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (s.isMarked == false && _canEdit && roster.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Not taken yet. Everyone starts as Present: tap the '
              'exceptions, then Save.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(notice, style: TextStyle(color: scheme.error)),
          ),
        if (_canEdit && roster.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _allPresent,
                icon: const Icon(Icons.done_all),
                label: const Text('All present'),
              ),
            ),
          ),
        const Divider(height: 24),
        if (roster.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No swimmers were in this group on this day.'),
          ),
        for (final e in roster) _swimmerRow(e),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'P present   A absent   L late   U early-up   '
            'D did not finish   E excused',
          ),
        ),
      ],
    );
  }

  Widget _swimmerRow(RosterEntry e) {
    final m = _marks[e.swimmerId]!;
    final edit = _canEdit;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.fullName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (edit || m.note != null)
                IconButton(
                  tooltip: m.note == null ? 'Add a note' : 'Edit note',
                  icon: Icon(
                    m.note == null
                        ? Icons.note_add_outlined
                        : Icons.sticky_note_2,
                  ),
                  onPressed: edit ? () => _editNote(e) : null,
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final st in attendanceStatuses)
                ChoiceChip(
                  label: Text(attendanceLetter(st)),
                  tooltip: attendanceLabel(st),
                  showCheckmark: false,
                  selected: m.status == st,
                  onSelected: edit ? (_) => _set(e.swimmerId, st) : null,
                ),
            ],
          ),
          if (m.status == 'excused')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Excused:',
                    style: TextStyle(
                      color: m.reason == null ? scheme.error : null,
                    ),
                  ),
                  for (final r in excuseReasons)
                    ChoiceChip(
                      label: Text(excuseLabel(r)),
                      selected: m.reason == r,
                      onSelected: edit
                          ? (_) => setState(() {
                              m.reason = r;
                              _changed = true;
                            })
                          : null,
                    ),
                ],
              ),
            ),
          if (m.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Note: ${m.note}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
