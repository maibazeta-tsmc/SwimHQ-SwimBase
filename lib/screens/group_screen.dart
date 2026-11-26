import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/move_history.dart';
import 'group_form.dart';
import 'groups_screen.dart';
import 'move_sheet.dart';
import 'schedule_tab.dart';
import 'swimmer_screen.dart';

/// One group's page: its swimmers (with Select to move several at once),
/// its training schedule and its history. [groupId] null means the Unassigned list.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.club, required this.groupId});
  final Membership club;
  final String? groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late Future<ClubData> _data = ClubData.load(widget.club.clubId);
  bool _selecting = false;
  final Set<String> _selected = {};
  int _historyVersion = 0;

  void _refresh() => setState(() {
    _data = ClubData.load(widget.club.clubId);
    _selected.clear();
    _selecting = false;
    _historyVersion++;
  });

  Future<void> _edit(Group group) async {
    final form = await showGroupForm(context, group: group);
    if (form == null || !mounted) return;
    final ok = await runAction(
      context,
      () => db.from('groups').update(form.toRow()).eq('id', group.id),
      done: 'Group saved.',
    );
    if (ok) _refresh();
  }

  /// Ticks which coaches look after this group.
  Future<void> _assignCoaches(Group group) async {
    final clubId = widget.club.clubId;
    List<Map<String, dynamic>> coaches;
    Set<String> assigned;
    try {
      final results = await Future.wait([
        db
            .from('club_members')
            .select('user_id')
            .eq('club_id', clubId)
            .inFilter('role', ['head_coach', 'assistant_coach']),
        db.from('group_coaches').select('user_id').eq('group_id', group.id),
      ]);
      final ids = [for (final r in results[0]) r['user_id'] as String];
      coaches = List<Map<String, dynamic>>.from(
        await db.from('profiles').select('id, full_name').inFilter('id', ids),
      );
      assigned = {for (final r in results[1]) r['user_id'] as String};
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load the coaches.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        final ticked = {...assigned};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Coaches for ${group.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in coaches)
                  CheckboxListTile(
                    value: ticked.contains(c['id']),
                    title: Text(
                      (c['full_name'] as String?)?.isNotEmpty == true
                          ? c['full_name'] as String
                          : 'Coach',
                    ),
                    onChanged: (v) => setDialogState(
                      () => v == true
                          ? ticked.add(c['id'] as String)
                          : ticked.remove(c['id']),
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
                onPressed: () => Navigator.pop(context, ticked),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    final add = chosen.difference(assigned);
    final remove = assigned.difference(chosen);
    await runAction(context, () async {
      if (add.isNotEmpty) {
        await db.from('group_coaches').insert([
          for (final id in add)
            {'group_id': group.id, 'club_id': clubId, 'user_id': id},
        ]);
      }
      if (remove.isNotEmpty) {
        await db
            .from('group_coaches')
            .delete()
            .eq('group_id', group.id)
            .inFilter('user_id', remove.toList());
      }
    }, done: 'Coaches saved.');
  }

  Future<void> _archive(Group group) async {
    final yes = await confirm(
      context,
      title: 'Archive ${group.name}?',
      message:
          'The group disappears from the list but its history is '
          'kept. You can restore it later. It must be empty first.',
      yes: 'Archive',
    );
    if (!yes || !mounted) return;
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      () => db
          .from('groups')
          .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', group.id),
      done: '${group.name} archived.',
    );
    if (ok) navigator.pop();
  }

  Future<void> _move(ClubData data, Group? group, List<Swimmer> who) async {
    final moved = await showMoveSheet(
      context,
      swimmers: who,
      from: group,
      groups: data.activeGroups,
      onUndone: () {
        if (mounted) _refresh();
      },
    );
    if (moved) _refresh();
  }

  Future<void> _openSwimmer(Swimmer s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwimmerScreen(club: widget.club, swimmerId: s.id),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ClubData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: LoadState(error: snapshot.error, onRetry: _refresh),
          );
        }
        final group = data.groupById(widget.groupId);
        final unassigned = widget.groupId == null;
        if (!unassigned && (group == null || group.archived)) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This group was archived.')),
          );
        }
        final swimmers = data.inGroup(widget.groupId);
        final club = widget.club;
        final title = unassigned
            ? 'Unassigned'
            : '${group!.name} (level ${group.level})';

        final swimmerList = _swimmerList(data, group, swimmers);
        return DefaultTabController(
          length: unassigned ? 1 : 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: [
                if (!unassigned && club.canManageGroups)
                  IconButton(
                    tooltip: 'Edit group',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _edit(group!),
                  ),
                if (!unassigned && club.canManageGroups)
                  PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'edit' => _edit(group!),
                      'coaches' => _assignCoaches(group!),
                      _ => _archive(group!),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit group')),
                      PopupMenuItem(
                        value: 'coaches',
                        child: Text('Assign coaches'),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text('Archive group'),
                      ),
                    ],
                  ),
              ],
              bottom: unassigned
                  ? null
                  : const TabBar(
                      tabs: [
                        Tab(text: 'Swimmers'),
                        Tab(text: 'Schedule'),
                        Tab(text: 'History'),
                      ],
                    ),
            ),
            bottomNavigationBar: _selecting
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _move(data, group, [
                                for (final s in swimmers)
                                  if (_selected.contains(s.id)) s,
                              ]),
                        icon: const Icon(Icons.swap_vert),
                        label: Text(
                          _selected.isEmpty
                              ? 'Tick the swimmers to move'
                              : 'Move ${_selected.length} to...',
                        ),
                      ),
                    ),
                  )
                : null,
            body: unassigned
                ? swimmerList
                : TabBarView(
                    children: [
                      swimmerList,
                      ScheduleTab(
                        club: club,
                        group: group!,
                        allGroups: data.activeGroups,
                      ),
                      ListView(
                        children: [
                          MoveHistory(
                            key: ValueKey(_historyVersion),
                            groups: data.groups,
                            groupId: group.id,
                            canCancel: club.canMove,
                            onChanged: _refresh,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _swimmerList(ClubData data, Group? group, List<Swimmer> swimmers) {
    final club = widget.club;
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    swimmers.length == 1
                        ? '1 swimmer'
                        : '${swimmers.length} swimmers',
                  ),
                ),
                if (club.canMove && swimmers.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _selecting = !_selecting;
                      _selected.clear();
                    }),
                    child: Text(_selecting ? 'Done' : 'Select'),
                  ),
                if (club.isCoach && !_selecting)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      if (await addSwimmer(
                        context,
                        club: club,
                        groups: data.activeGroups,
                        startGroupId: group?.id,
                      )) {
                        _refresh();
                      }
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add'),
                  ),
              ],
            ),
          ),
          if (_selecting && swimmers.isNotEmpty)
            CheckboxListTile(
              title: const Text('Select all'),
              value: _selected.length == swimmers.length,
              onChanged: (all) => setState(() {
                _selected.clear();
                if (all == true) _selected.addAll(swimmers.map((s) => s.id));
              }),
            ),
          if (swimmers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                group == null
                    ? 'Everyone has a group.'
                    : 'No swimmers in this group yet. Tap Add, or move '
                          'swimmers here from another group.',
              ),
            ),
          for (final s in swimmers)
            _selecting
                ? CheckboxListTile(
                    value: _selected.contains(s.id),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _selected.add(s.id)
                          : _selected.remove(s.id),
                    ),
                    title: Text(s.fullName),
                    subtitle: Text('Age ${ageOn(s.birthDate)}'),
                  )
                : ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        s.firstName.isEmpty
                            ? '?'
                            : s.firstName[0].toUpperCase(),
                      ),
                    ),
                    title: Text(s.fullName),
                    subtitle: Text(
                      'Age ${ageOn(s.birthDate)}'
                      '${s.hasLogin ? '' : '  ·  no login yet'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openSwimmer(s),
                    onLongPress: club.canMove
                        ? () => _move(data, group, [s])
                        : null,
                  ),
        ],
      ),
    );
  }
}
