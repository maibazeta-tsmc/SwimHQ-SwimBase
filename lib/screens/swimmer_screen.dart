import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/move_history.dart';
import 'groups_screen.dart';
import 'invite_dialog.dart';
import 'move_sheet.dart';
import 'swimmer_form.dart';

/// A swimmer's profile as coaches see it: details, current group, move
/// buttons and their full group history.
class SwimmerScreen extends StatefulWidget {
  const SwimmerScreen({super.key, required this.club, required this.swimmerId});
  final Membership club;
  final String swimmerId;

  @override
  State<SwimmerScreen> createState() => _SwimmerScreenState();
}

class _SwimmerScreenState extends State<SwimmerScreen> {
  late Future<ClubData> _data = ClubData.load(widget.club.clubId);
  late Future<List<Map<String, dynamic>>> _parents = _loadParents();
  int _version = 0;

  void _refresh() => setState(() {
    _data = ClubData.load(widget.club.clubId);
    _parents = _loadParents();
    _version++;
  });

  /// The parents linked to this swimmer, with their names.
  Future<List<Map<String, dynamic>>> _loadParents() async {
    final links = List<Map<String, dynamic>>.from(
      await db
          .from('parent_links')
          .select('id, parent_user_id')
          .eq('swimmer_id', widget.swimmerId),
    );
    if (links.isEmpty) return links;
    final people = await db
        .from('profiles')
        .select('id, full_name, email')
        .inFilter('id', [for (final l in links) l['parent_user_id']]);
    final byId = {for (final p in people) p['id']: p};
    for (final l in links) {
      l['profile'] = byId[l['parent_user_id']];
    }
    return links;
  }

  Future<void> _invite(Swimmer s, String role) async {
    if (await createAndShowInvite(
      context,
      clubId: widget.club.clubId,
      role: role,
      swimmerId: s.id,
      forWhom: s.fullName,
    )) {
      _refresh();
    }
  }

  Future<void> _unlinkParent(Map<String, dynamic> link, String name) async {
    final yes = await confirm(
      context,
      title: 'Unlink $name?',
      message: '$name will no longer see this swimmer.',
      yes: 'Unlink',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(
      context,
      () => db.from('parent_links').delete().eq('id', link['id']),
      done: '$name unlinked.',
    );
    if (ok) _refresh();
  }

  List<Widget> _family(Swimmer swimmer) {
    final club = widget.club;
    final canInvite = club.isCoach && !club.isPending;
    return [
      ListTile(
        leading: Icon(
          swimmer.hasLogin
              ? Icons.verified_user_outlined
              : Icons.no_accounts_outlined,
        ),
        title: Text(swimmer.hasLogin ? 'Has their own login' : 'No login yet'),
        subtitle: club.isCoach && club.isPending
            ? const Text(
                'Invite codes for swimmers and parents open once your '
                'club is approved.',
              )
            : null,
        trailing: canInvite && !swimmer.hasLogin
            ? FilledButton.tonal(
                onPressed: () => _invite(swimmer, 'swimmer'),
                child: const Text('Make login code'),
              )
            : null,
      ),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _parents,
        builder: (context, snapshot) {
          final links = snapshot.data ?? const [];
          return Column(
            children: [
              for (final l in links)
                ListTile(
                  leading: const Icon(Icons.family_restroom),
                  title: Text(
                    (l['profile']?['full_name'] as String?)?.isNotEmpty == true
                        ? l['profile']['full_name'] as String
                        : 'Parent',
                  ),
                  subtitle: Text('Parent  ·  ${l['profile']?['email'] ?? ''}'),
                  trailing: club.isCoach
                      ? IconButton(
                          tooltip: 'Unlink parent',
                          icon: const Icon(Icons.link_off),
                          onPressed: () => _unlinkParent(
                            l,
                            l['profile']?['full_name'] as String? ?? 'Parent',
                          ),
                        )
                      : null,
                ),
              if (canInvite)
                ListTile(
                  leading: const Icon(Icons.add_link),
                  title: const Text('Invite a parent'),
                  subtitle: const Text('Makes a one-time parent code'),
                  onTap: () => _invite(swimmer, 'parent'),
                ),
            ],
          );
        },
      ),
    ];
  }

  Future<void> _edit(Swimmer s) async {
    final form = await showSwimmerForm(context, swimmer: s);
    if (form == null || !mounted) return;
    final ok = await runAction(
      context,
      () => db
          .from('swimmers')
          .update({
            'first_name': form.firstName,
            'last_name': form.lastName,
            'birth_date': dbDate(form.birthDate),
            'gender': form.gender,
          })
          .eq('id', s.id),
      done: 'Details saved.',
    );
    if (ok) _refresh();
  }

  Future<void> _markLeft(Swimmer s) async {
    final yes = await confirm(
      context,
      title: '${s.firstName} has left the club?',
      message:
          '${s.fullName} will drop out of the group lists and their '
          'parents\' links will end. Their history and times are kept.',
      yes: 'Mark as left',
    );
    if (!yes || !mounted) return;
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      () => db.rpc('mark_swimmer_left', params: {'p_swimmer_id': s.id}),
      done: '${s.fullName} marked as left.',
    );
    if (ok) navigator.pop();
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
        Swimmer? s;
        for (final x in data.swimmers) {
          if (x.id == widget.swimmerId) s = x;
        }
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This swimmer has left the club.')),
          );
        }
        final swimmer = s;
        final group = data.groupById(swimmer.currentGroupId);
        final club = widget.club;
        return Scaffold(
          appBar: AppBar(
            title: Text(swimmer.fullName),
            actions: [
              if (club.isCoach)
                PopupMenuButton<String>(
                  onSelected: (v) =>
                      v == 'edit' ? _edit(swimmer) : _markLeft(swimmer),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit details')),
                    PopupMenuItem(
                      value: 'left',
                      child: Text('Mark as left the club'),
                    ),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ListTile(
                leading: LevelBadge(level: group?.level, colour: group?.colour),
                title: Text(group?.name ?? 'No group yet'),
                subtitle: const Text('Current group'),
              ),
              ListTile(
                leading: const Icon(Icons.cake_outlined),
                title: Text('Age ${ageOn(swimmer.birthDate)}'),
                subtitle: Text(
                  'Born ${formatDate(swimmer.birthDate)}  ·  '
                  '${swimmer.gender == 'male' ? 'Male' : 'Female'}',
                ),
              ),
              ..._family(swimmer),
              if (club.canMove)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final moved = await showMoveSheet(
                        context,
                        swimmers: [swimmer],
                        from: group,
                        groups: data.activeGroups,
                        onUndone: () {
                          if (mounted) _refresh();
                        },
                      );
                      if (moved) _refresh();
                    },
                    icon: const Icon(Icons.swap_vert),
                    label: Text(group == null ? 'Put in a group' : 'Move'),
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Group history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              MoveHistory(
                key: ValueKey(_version),
                groups: data.groups,
                swimmerId: swimmer.id,
                canCancel: club.canMove,
                onChanged: _refresh,
              ),
            ],
          ),
        );
      },
    );
  }
}
