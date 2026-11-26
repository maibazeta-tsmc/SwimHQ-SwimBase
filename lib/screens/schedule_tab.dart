import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'schedule_forms.dart';

/// Everything the Schedule tab shows for one group.
class _ScheduleData {
  _ScheduleData(this.canEdit, this.weekly, this.sessions, this.restDays);
  final bool canEdit;
  final List<WeeklySession> weekly;
  final List<TrainingSession> sessions; // the next 4 weeks
  final List<RestDay> restDays; // this group's and the whole club's

  static Future<_ScheduleData> load(String clubId, String groupId) async {
    final today = dbDate(dateOnly());
    final until = dbDate(dateOnly().add(const Duration(days: 27)));
    final results = await Future.wait<dynamic>([
      db.rpc('can_edit_schedule', params: {'p_group_id': groupId}),
      db
          .from('weekly_sessions')
          .select()
          .eq('group_id', groupId)
          .or('ends_on.is.null,ends_on.gte.$today')
          .order('weekday')
          .order('start_time'),
      db
          .from('sessions')
          .select()
          .eq('group_id', groupId)
          .gte('session_date', today)
          .lte('session_date', until)
          .order('session_date')
          .order('start_time'),
      db
          .from('rest_days')
          .select()
          .eq('club_id', clubId)
          .or('group_id.is.null,group_id.eq.$groupId')
          .gte('end_date', today)
          .order('start_date'),
    ]);
    return _ScheduleData(
      results[0] == true,
      [for (final r in results[1]) WeeklySession.fromRow(r)],
      [for (final r in results[2]) TrainingSession.fromRow(r)],
      [for (final r in results[3]) RestDay.fromRow(r)],
    );
  }
}

/// A group's Schedule tab: the weekly pattern, rest days, and the actual
/// sessions for the next 4 weeks. Coaches who may edit it get buttons.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({
    super.key,
    required this.club,
    required this.group,
    required this.allGroups,
  });
  final Membership club;
  final Group group;
  final List<Group> allGroups; // active groups of the club

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  late Future<_ScheduleData> _data = _load();

  Future<_ScheduleData> _load() =>
      _ScheduleData.load(widget.club.clubId, widget.group.id);

  void _refresh() => setState(() => _data = _load());

  Future<void> _rpc(String fn, Map<String, dynamic> params, String done) async {
    final ok = await runAction(
      context,
      () => db.rpc(fn, params: params),
      done: done,
    );
    if (ok && mounted) _refresh();
  }

  // ----- Weekly pattern -----

  Future<void> _addWeekly() async {
    final form = await showWeeklyForm(context);
    if (form == null || !mounted) return;
    final days = form.weekdays.toList()..sort();
    final ok = await runAction(context, () async {
      for (final d in days) {
        await db.rpc(
          'add_weekly_session',
          params: {
            'p_group_id': widget.group.id,
            'p_weekday': d,
            'p_start_time': dbTime(form.start),
            'p_end_time': dbTime(form.end),
            'p_label': form.label,
            'p_venue': form.venue,
            'p_starts_on': dbDate(form.startsOn),
          },
        );
      }
    }, done: 'Weekly session added. Sessions are on the calendar.');
    if (ok && mounted) _refresh();
  }

  Future<void> _removeWeekly(WeeklySession w) async {
    final yes = await confirm(
      context,
      title:
          'Remove ${weekdayNames[w.weekday - 1]} '
          '${timeRange(w.start, w.end)}?',
      message:
          'It comes off the weekly schedule from today. Sessions '
          'that already happened stay as they were.',
      yes: 'Remove',
    );
    if (!yes || !mounted) return;
    await _rpc('end_weekly_session', {
      'p_weekly_session_id': w.id,
    }, 'Removed from the weekly schedule.');
  }

  Future<void> _copyFrom() async {
    final others = [
      for (final g in widget.allGroups)
        if (g.id != widget.group.id) g,
    ];
    if (others.isEmpty) return;
    final from = await showDialog<Group>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Copy the weekly schedule from'),
        children: [
          for (final g in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, g),
              child: Text(g.name),
            ),
        ],
      ),
    );
    if (from == null || !mounted) return;
    await _rpc('copy_weekly_schedule', {
      'p_from_group_id': from.id,
      'p_to_group_id': widget.group.id,
    }, 'Copied ${from.name}\'s weekly schedule.');
  }

  // ----- Rest days -----

  Future<void> _addRest() async {
    final form = await showRestForm(
      context,
      groupName: widget.group.name,
      canDoWholeClub: widget.club.canManageGroups,
    );
    if (form == null || !mounted) return;
    await _rpc('add_rest_days', {
      'p_club_id': widget.club.clubId,
      'p_group_ids': form.wholeClub ? <String>[] : [widget.group.id],
      'p_start': dbDate(form.start),
      'p_end': dbDate(form.end),
      'p_kind': form.isBreak ? 'break' : 'rest_day',
      'p_title': form.title,
    }, form.isBreak ? 'Break added.' : 'Rest day added.');
  }

  Future<void> _removeRest(RestDay r) async {
    final yes = await confirm(
      context,
      title: 'Remove ${r.name}?',
      message: 'The sessions it cancelled come back.',
      yes: 'Remove',
    );
    if (!yes || !mounted) return;
    await _rpc('remove_rest_day', {
      'p_rest_day_id': r.id,
    }, '${r.name} removed.');
  }

  // ----- One day -----

  Future<void> _addOneOff() async {
    // Only offer groups this coach may edit; the database checks again.
    final groups = widget.club.canManageGroups
        ? widget.allGroups
        : [widget.group];
    final form = await showOneOffForm(
      context,
      groupId: widget.group.id,
      groups: groups,
    );
    if (form == null || !mounted) return;
    await _rpc('add_one_off_session', {
      'p_group_ids': form.groupIds,
      'p_date': dbDate(form.date),
      'p_start_time': dbTime(form.start),
      'p_end_time': dbTime(form.end),
      'p_label': form.label,
      'p_venue': form.venue,
    }, 'Session added for ${formatDayShort(form.date)}.');
  }

  Future<void> _sessionActions(TrainingSession s) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${formatDayShort(s.date)}  ${timeRange(s.start, s.end)}',
              ),
              subtitle: s.label == null ? null : Text(s.label!),
            ),
            if (!s.cancelled) ...[
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Change the time for this day'),
                onTap: () => Navigator.pop(context, 'time'),
              ),
              ListTile(
                leading: const Icon(Icons.event_busy),
                title: const Text('Cancel this session'),
                onTap: () => Navigator.pop(context, 'cancel'),
              ),
            ] else if (s.restDayId == null)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Bring this session back'),
                onTap: () => Navigator.pop(context, 'restore'),
              )
            else
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text(
                  'Cancelled by a rest day. Remove the rest day to bring '
                  'it back.',
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'time':
        final t = await showTimeChangeForm(context, s);
        if (t == null || !mounted) return;
        await _rpc('change_session_time', {
          'p_session_id': s.id,
          'p_start_time': dbTime(t.start),
          'p_end_time': dbTime(t.end),
        }, 'Time changed for ${formatDayShort(s.date)}.');
      case 'cancel':
        final reason = await askCancelReason(
          context,
          'the ${formatDayShort(s.date)} session',
        );
        if (reason == null || !mounted) return;
        await _rpc('cancel_sessions', {
          'p_session_ids': [s.id],
          'p_reason': reason,
        }, 'Session cancelled.');
      case 'restore':
        await _rpc('restore_session', {
          'p_session_id': s.id,
        }, 'Session is back on.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ScheduleData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return LoadState(error: snapshot.error, onRetry: _refresh);
        }
        final text = Theme.of(context).textTheme;
        final edit = data.canEdit;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _heading('Weekly', text),
              if (data.weekly.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('No weekly sessions yet.'),
                ),
              for (var d = 1; d <= 7; d++) _weekdayRow(d, data, edit),
              if (edit)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _addWeekly,
                        icon: const Icon(Icons.add),
                        label: const Text('Weekly session'),
                      ),
                      if (widget.allGroups.length > 1)
                        OutlinedButton.icon(
                          onPressed: _copyFrom,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy from a group'),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 32),
              _heading('Rest days and breaks', text),
              if (data.restDays.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('None coming up.'),
                ),
              for (final r in data.restDays)
                ListTile(
                  leading: const Icon(Icons.beach_access),
                  title: Text(r.name),
                  subtitle: Text(
                    '${r.startDate == r.endDate ? formatDayShort(r.startDate) : '${formatDayShort(r.startDate)} to ${formatDayShort(r.endDate)}'}'
                    '${r.groupId == null ? '  ·  whole club' : ''}',
                  ),
                  trailing:
                      edit && (r.groupId != null || widget.club.canManageGroups)
                      ? IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeRest(r),
                        )
                      : null,
                ),
              if (edit)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _addRest,
                      icon: const Icon(Icons.add),
                      label: const Text('Rest days'),
                    ),
                  ),
                ),
              const Divider(height: 32),
              _heading('Next 4 weeks', text),
              if (data.sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('No sessions in the next 4 weeks.'),
                ),
              for (final s in data.sessions) _sessionTile(s, data, edit),
              if (edit)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _addOneOff,
                      icon: const Icon(Icons.add),
                      label: const Text('One-off session'),
                    ),
                  ),
                ),
              if (!edit)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Only the head coach and this group\'s coaches can '
                    'change this schedule.',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _heading(String title, TextTheme text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(title, style: text.titleMedium),
  );

  Widget _weekdayRow(int weekday, _ScheduleData data, bool edit) {
    final lines = data.weekly.where((w) => w.weekday == weekday).toList();
    final today = dateOnly();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 48, child: Text(weekdayShort(weekday))),
          Expanded(
            child: lines.isEmpty
                ? Text(
                    'rest',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final w in lines)
                        InputChip(
                          label: Text(
                            [
                              timeRange(w.start, w.end),
                              if (w.label != null) w.label!,
                              if (w.startsOn.isAfter(today))
                                'from ${formatDayShort(w.startsOn)}',
                              if (w.endsOn != null)
                                'until ${formatDayShort(w.endsOn!)}',
                            ].join('  ·  '),
                          ),
                          onDeleted: edit ? () => _removeWeekly(w) : null,
                          deleteButtonTooltipMessage: 'Remove',
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sessionTile(TrainingSession s, _ScheduleData data, bool edit) {
    String? restName;
    if (s.restDayId != null) {
      for (final r in data.restDays) {
        if (r.id == s.restDayId) restName = r.name;
      }
    }
    final details = [
      if (s.label != null) s.label!,
      if (s.venue != null) s.venue!,
      if (s.oneOff) 'one-off',
      if (s.cancelled)
        'Cancelled${s.cancelReason != null
            ? ': ${s.cancelReason}'
            : restName != null
            ? ': $restName'
            : ''}',
    ];
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(
        s.cancelled ? Icons.event_busy : Icons.pool,
        color: s.cancelled ? scheme.error : scheme.primary,
      ),
      title: Text(
        '${formatDayShort(s.date)}   ${timeRange(s.start, s.end)}',
        style: s.cancelled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: details.isEmpty ? null : Text(details.join('  ·  ')),
      onTap: edit ? () => _sessionActions(s) : null,
    );
  }
}
