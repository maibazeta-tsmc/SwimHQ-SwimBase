import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'group_form.dart';
import 'group_screen.dart';
import 'swimmer_form.dart';

/// Loads every group and active swimmer of one club. Shared by the Groups
/// list and the group pages so they always agree.
class ClubData {
  ClubData(this.groups, this.swimmers);
  final List<Group> groups; // includes archived ones
  final List<Swimmer> swimmers; // active swimmers only

  static Future<ClubData> load(String clubId) async {
    final results = await Future.wait([
      db.from('groups').select().eq('club_id', clubId),
      db
          .from('swimmers')
          .select(swimmerColumns)
          .eq('club_id', clubId)
          .eq('status', 'active')
          .order('last_name')
          .order('first_name'),
    ]);
    return ClubData(
      [for (final r in results[0]) Group.fromRow(r)],
      [for (final r in results[1]) Swimmer.fromRow(r)],
    );
  }

  List<Group> get activeGroups => sortGroups(groups);
  List<Group> get archivedGroups =>
      groups.where((g) => g.archived).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<Swimmer> inGroup(String? groupId) =>
      swimmers.where((s) => s.currentGroupId == groupId).toList();

  Group? groupById(String? id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// Adds a swimmer to the club (asking for their details first).
/// Returns true if a swimmer was added.
Future<bool> addSwimmer(
  BuildContext context, {
  required Membership club,
  required List<Group> groups,
  String? startGroupId,
}) async {
  final form = await showSwimmerForm(
    context,
    groups: groups,
    startGroupId: startGroupId,
  );
  if (form == null || !context.mounted) return false;
  return runAction(
    context,
    () => db.from('swimmers').insert({
      'club_id': club.clubId,
      'first_name': form.firstName,
      'last_name': form.lastName,
      'birth_date': dbDate(form.birthDate),
      'gender': form.gender,
      'current_group_id': form.groupId,
    }),
    done: '${form.firstName} ${form.lastName} added.',
  );
}

/// The Groups tab: the club's groups from top level down, with swimmer
/// counts, plus Unassigned and Archived.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.club});
  final Membership club;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late Future<ClubData> _data = ClubData.load(widget.club.clubId);

  void _refresh() => setState(() => _data = ClubData.load(widget.club.clubId));

  Future<void> _newGroup(ClubData data) async {
    final topLevel = data.activeGroups.isEmpty
        ? 0
        : data.activeGroups.map((g) => g.level).reduce((a, b) => a > b ? a : b);
    final form = await showGroupForm(context, suggestedLevel: topLevel + 1);
    if (form == null || !mounted) return;
    final ok = await runAction(
      context,
      () => db.from('groups').insert({
        ...form.toRow(),
        'club_id': widget.club.clubId,
        'created_by': db.auth.currentUser!.id,
      }),
      done: 'Group ${form.name} created.',
    );
    if (ok) _refresh();
  }

  Future<void> _openGroup(ClubData data, Group? group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupScreen(club: widget.club, groupId: group?.id),
      ),
    );
    _refresh();
  }

  Future<void> _editGroup(Group g) async {
    final form = await showGroupForm(context, group: g);
    if (form == null || !mounted) return;
    final ok = await runAction(
      context,
      () => db.from('groups').update(form.toRow()).eq('id', g.id),
      done: 'Group saved.',
    );
    if (ok) _refresh();
  }

  Future<void> _restore(Group g) async {
    final ok = await runAction(
      context,
      () => db.from('groups').update({'archived_at': null}).eq('id', g.id),
      done: '${g.name} restored.',
    );
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    return FutureBuilder<ClubData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          floatingActionButton: data == null
              ? null
              : club.canManageGroups
              ? FloatingActionButton.extended(
                  onPressed: () => _newGroup(data),
                  icon: const Icon(Icons.add),
                  label: const Text('New group'),
                )
              : club.isCoach
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    if (await addSwimmer(
                      context,
                      club: club,
                      groups: data.activeGroups,
                    )) {
                      _refresh();
                    }
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add swimmer'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: data == null
                ? ListView(
                    children: [
                      LoadState(error: snapshot.error, onRetry: _refresh),
                    ],
                  )
                : _list(context, data),
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, ClubData data) {
    final club = widget.club;
    final unassigned = data.inGroup(null).length;
    final archived = data.archivedGroups;
    String count(int n) => n == 1 ? '1 swimmer' : '$n swimmers';

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (club.isPending)
          const Card(
            margin: EdgeInsets.all(12),
            child: ListTile(
              leading: Icon(Icons.hourglass_top),
              title: Text('Your club is waiting for approval'),
              subtitle: Text(
                'You can set up groups and add swimmers now. '
                'Invites for swimmers and parents open once it is '
                'approved.',
              ),
            ),
          ),
        if (data.activeGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              club.canManageGroups
                  ? 'No groups yet. Tap New group to make your first one, '
                        'for example Bronze (level 1), Silver (2), Gold (3).'
                  : 'No groups yet. Your head coach sets them up.',
            ),
          ),
        for (final g in data.activeGroups)
          ListTile(
            leading: LevelBadge(level: g.level, colour: g.colour),
            title: Text(g.name),
            subtitle: g.description == null ? null : Text(g.description!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(count(data.inGroup(g.id).length)),
                if (club.canManageGroups)
                  IconButton(
                    tooltip: 'Edit group',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editGroup(g),
                  )
                else
                  const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _openGroup(data, g),
          ),
        const Divider(),
        ListTile(
          leading: const LevelBadge(level: null),
          title: const Text('Unassigned'),
          subtitle: const Text('Swimmers without a group yet'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(count(unassigned)),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => _openGroup(data, null),
        ),
        if (archived.isNotEmpty)
          ExpansionTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('Archived (${archived.length})'),
            children: [
              for (final g in archived)
                ListTile(
                  title: Text(g.name),
                  subtitle: Text('Level ${g.level}'),
                  trailing: club.canManageGroups
                      ? TextButton(
                          onPressed: () => _restore(g),
                          child: const Text('Restore'),
                        )
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}
