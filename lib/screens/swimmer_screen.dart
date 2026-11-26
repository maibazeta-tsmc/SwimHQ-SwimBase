import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/move_history.dart';
import 'groups_screen.dart';
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
  int _version = 0;

  void _refresh() => setState(() {
    _data = ClubData.load(widget.club.clubId);
    _version++;
  });

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
                  '${swimmer.gender == 'male' ? 'Boy' : 'Girl'}',
                ),
              ),
              ListTile(
                leading: Icon(
                  swimmer.hasLogin
                      ? Icons.verified_user_outlined
                      : Icons.no_accounts_outlined,
                ),
                title: Text(
                  swimmer.hasLogin ? 'Has their own login' : 'No login yet',
                ),
                subtitle: swimmer.hasLogin
                    ? null
                    : const Text(
                        'Invite codes for swimmers and parents '
                        'come in the next update.',
                      ),
              ),
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
