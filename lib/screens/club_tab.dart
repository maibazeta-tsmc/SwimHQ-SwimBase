import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'invite_dialog.dart';

/// The Club tab: the club's coaches with their permission switches, coach
/// invites, the list of every invite code, and the head coach handover.
class ClubTab extends StatefulWidget {
  const ClubTab({super.key, required this.club, required this.onRoleChanged});
  final Membership club;

  /// Called when the signed-in person's own role changed (handover).
  final VoidCallback onRoleChanged;

  @override
  State<ClubTab> createState() => _ClubTabState();
}

class _Coach {
  _Coach(
    this.memberId,
    this.userId,
    this.role,
    this.canCreateGroups,
    this.canMoveSwimmers,
    this.name,
    this.email,
    this.groups,
  );
  final String memberId;
  final String userId;
  final String role;
  final bool canCreateGroups;
  final bool canMoveSwimmers;
  final String name;
  final String email;
  final List<String> groups;
  bool get isHead => role == 'head_coach';
}

class _ClubInfo {
  _ClubInfo(this.coaches, this.invites);
  final List<_Coach> coaches;
  final List<Map<String, dynamic>> invites;
}

class _ClubTabState extends State<ClubTab> {
  late Future<_ClubInfo> _info = _load();

  String get _clubId => widget.club.clubId;
  bool get _isHead => widget.club.isHeadCoach;

  Future<_ClubInfo> _load() async {
    final results = await Future.wait([
      db
          .from('club_members')
          .select('id, user_id, role, can_create_groups, can_move_swimmers')
          .eq('club_id', _clubId)
          .inFilter('role', ['head_coach', 'assistant_coach']),
      db
          .from('group_coaches')
          .select('user_id, groups(name, archived_at)')
          .eq('club_id', _clubId),
      db
          .from('invite_codes')
          .select(
            'id, role, code, expires_at, used_at, created_at, '
            'swimmers(first_name, last_name)',
          )
          .eq('club_id', _clubId)
          .order('created_at', ascending: false)
          .limit(100),
    ]);
    final members = results[0];
    final ids = [for (final m in members) m['user_id'] as String];
    final people = ids.isEmpty
        ? const <Map<String, dynamic>>[]
        : await db
              .from('profiles')
              .select('id, full_name, email')
              .inFilter('id', ids);
    final byId = {for (final p in people) p['id']: p};
    final groupsOf = <String, List<String>>{};
    for (final gc in results[1]) {
      final g = gc['groups'] as Map?;
      if (g == null || g['archived_at'] != null) continue;
      groupsOf.putIfAbsent(gc['user_id'] as String, () => []).add(g['name']);
    }
    final coaches =
        [
          for (final m in members)
            _Coach(
              m['id'] as String,
              m['user_id'] as String,
              m['role'] as String,
              m['can_create_groups'] == true,
              m['can_move_swimmers'] == true,
              (byId[m['user_id']]?['full_name'] as String?)
                          ?.trim()
                          .isNotEmpty ==
                      true
                  ? byId[m['user_id']]!['full_name'] as String
                  : 'Coach',
              byId[m['user_id']]?['email'] as String? ?? '',
              groupsOf[m['user_id']] ?? const [],
            ),
        ]..sort(
          (a, b) => a.isHead != b.isHead
              ? (a.isHead ? -1 : 1)
              : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return _ClubInfo(coaches, List<Map<String, dynamic>>.from(results[2]));
  }

  void _refresh() => setState(() => _info = _load());

  Future<void> _setPermissions(
    _Coach c, {
    bool? createGroups,
    bool? moveSwimmers,
  }) async {
    final ok = await runAction(
      context,
      () => db.rpc(
        'set_coach_permissions',
        params: {
          'p_member_id': c.memberId,
          'p_can_create_groups': createGroups ?? c.canCreateGroups,
          'p_can_move_swimmers': moveSwimmers ?? c.canMoveSwimmers,
        },
      ),
      done: 'Saved. ${c.name} sees the change next time they open the club.',
    );
    if (ok) _refresh();
  }

  Future<void> _remove(_Coach c) async {
    final yes = await confirm(
      context,
      title: 'Remove ${c.name}?',
      message:
          '${c.name} loses access to the club straight away. Moves '
          'they made keep their name in the history.',
      yes: 'Remove',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(
      context,
      () => db.from('club_members').delete().eq('id', c.memberId),
      done: '${c.name} removed.',
    );
    if (ok) _refresh();
  }

  Future<void> _handOver(List<_Coach> coaches) async {
    final assistants = coaches.where((c) => !c.isHead).toList();
    if (assistants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invite another coach first. The head coach role '
            'can only go to a coach already in the club.',
          ),
        ),
      );
      return;
    }
    final picked = await showDialog<_Coach>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Hand over head coach to...'),
        children: [
          for (final c in assistants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c),
              child: Text(c.name),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final yes = await confirm(
      context,
      title: 'Make ${picked.name} head coach?',
      message:
          'You become an assistant coach. Only ${picked.name} (or the '
          'app owner) can give the role back.',
      yes: 'Hand over',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(
      context,
      () => db.rpc(
        'transfer_head_coach',
        params: {'p_club_id': _clubId, 'p_new_head_user_id': picked.userId},
      ),
      done: '${picked.name} is now head coach.',
    );
    if (ok) widget.onRoleChanged();
  }

  Future<void> _cancelInvite(Map<String, dynamic> invite) async {
    final ok = await runAction(
      context,
      () => db.from('invite_codes').delete().eq('id', invite['id']),
      done: 'Code ${invite['code']} cancelled.',
    );
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ClubInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return ListView(
            children: [LoadState(error: snapshot.error, onRetry: _refresh)],
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _header(
                context,
                'Coaches',
                action: _isHead
                    ? FilledButton.tonalIcon(
                        onPressed: () async {
                          if (await createAndShowInvite(
                            context,
                            clubId: _clubId,
                            role: 'assistant_coach',
                            forWhom: 'a coach',
                          )) {
                            _refresh();
                          }
                        },
                        icon: const Icon(Icons.person_add),
                        label: const Text('Invite a coach'),
                      )
                    : null,
              ),
              for (final c in info.coaches) _coachCard(c),
              if (_isHead)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => _handOver(info.coaches),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Hand over head coach role'),
                  ),
                ),
              const SizedBox(height: 16),
              _header(context, 'Invite codes'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Make swimmer and parent codes from a swimmer\'s profile '
                  '(Groups tab, then tap a swimmer).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (info.invites.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No invite codes yet.'),
                ),
              for (final inv in info.invites) _inviteTile(inv),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _coachCard(_Coach c) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: Icon(c.isHead ? Icons.star : Icons.sports),
            title: Text(c.name),
            subtitle: Text(
              [
                c.isHead ? 'Head coach' : 'Assistant coach',
                if (c.email.isNotEmpty) c.email,
                if (c.groups.isNotEmpty) 'Groups: ${c.groups.join(', ')}',
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing: _isHead && !c.isHead
                ? IconButton(
                    tooltip: 'Remove coach',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _remove(c),
                  )
                : null,
          ),
          if (!c.isHead) ...[
            SwitchListTile(
              dense: true,
              title: const Text('Can move swimmers'),
              value: c.canMoveSwimmers,
              onChanged: _isHead
                  ? (v) => _setPermissions(c, moveSwimmers: v)
                  : null,
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Can create and edit groups'),
              value: c.canCreateGroups,
              onChanged: _isHead
                  ? (v) => _setPermissions(c, createGroups: v)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _inviteTile(Map<String, dynamic> inv) {
    final used = inv['used_at'] != null;
    final expired =
        !used &&
        DateTime.parse(inv['expires_at'] as String).isBefore(DateTime.now());
    final swimmer = inv['swimmers'] as Map?;
    final name = swimmer == null
        ? null
        : '${swimmer['first_name']} ${swimmer['last_name']}';
    final what = switch (inv['role']) {
      'assistant_coach' => 'Coach',
      'swimmer' => 'Swimmer login for $name',
      _ => 'Parent of $name',
    };
    final status = used
        ? 'Joined'
        : expired
        ? 'Expired'
        : 'Pending, expires '
              '${formatDate(DateTime.parse(inv['expires_at'] as String).toLocal())}';
    return ListTile(
      leading: Icon(
        used
            ? Icons.check_circle_outline
            : expired
            ? Icons.timer_off_outlined
            : Icons.hourglass_empty,
      ),
      title: Text('${inv['code']}  ·  $what'),
      subtitle: Text(status),
      onTap: used || expired
          ? null
          : () => showInviteCode(
              context,
              code: inv['code'] as String,
              role: inv['role'] as String,
              forWhom: name ?? 'a coach',
            ),
      trailing: used
          ? null
          : IconButton(
              tooltip: 'Cancel code',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _cancelInvite(inv),
            ),
    );
  }
}
