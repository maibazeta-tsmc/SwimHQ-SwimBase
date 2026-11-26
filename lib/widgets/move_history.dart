import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import 'common.dart';

/// A timeline of group moves (newest first), for one swimmer or one group.
/// Coaches see everything, including reasons and who made each move.
/// Scheduled moves can be cancelled by coaches allowed to move swimmers.
class MoveHistory extends StatefulWidget {
  const MoveHistory({
    super.key,
    required this.groups,
    this.swimmerId,
    this.groupId,
    this.canCancel = false,
    this.onChanged,
  }) : assert(swimmerId != null || groupId != null);

  final List<Group> groups;
  final String? swimmerId;
  final String? groupId;
  final bool canCancel;
  final VoidCallback? onChanged;

  @override
  State<MoveHistory> createState() => _MoveHistoryState();
}

class _MoveHistoryState extends State<MoveHistory> {
  late Future<_Loaded> _moves = _load();

  Future<_Loaded> _load() async {
    var query = db
        .from('group_moves')
        .select(
          'id, swimmer_id, from_group_id, to_group_id, direction, '
          'effective_date, reason, share_reason, status, moved_by, recorded_at, '
          'swimmers(first_name, last_name)',
        );
    if (widget.swimmerId != null) {
      query = query.eq('swimmer_id', widget.swimmerId!);
    } else {
      final id = widget.groupId!;
      query = query.or('to_group_id.eq.$id,from_group_id.eq.$id');
    }
    final rows = List<Map<String, dynamic>>.from(
      await query.order('recorded_at', ascending: false).limit(200),
    );

    // Names of the coaches who made the moves.
    final coachIds = {
      for (final r in rows)
        if (r['moved_by'] != null) r['moved_by'] as String,
    };
    final names = <String, String>{};
    if (coachIds.isNotEmpty) {
      final people = await db
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', coachIds.toList());
      for (final p in people) {
        names[p['id'] as String] = p['full_name'] as String? ?? '';
      }
    }
    return _Loaded(rows, names);
  }

  void _refresh() => setState(() => _moves = _load());

  String _groupName(String? id) {
    if (id == null) return 'no group';
    for (final g in widget.groups) {
      if (g.id == id) return g.name;
    }
    return 'a removed group';
  }

  Future<void> _cancel(Map<String, dynamic> move) async {
    final yes = await confirm(
      context,
      title: 'Cancel this move?',
      message: 'The swimmer stays where they are.',
      yes: 'Cancel move',
    );
    if (!yes || !mounted) return;
    final ok = await runAction(
      context,
      () => db.rpc('cancel_scheduled_move', params: {'p_move_id': move['id']}),
      done: 'Scheduled move cancelled.',
    );
    if (ok) {
      _refresh();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Loaded>(
      future: _moves,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return LoadState(error: snapshot.error, onRetry: _refresh);
        }
        if (data.rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No moves yet.'),
          );
        }
        final outline = Theme.of(context).colorScheme.outline;
        return Column(
          children: [for (final m in data.rows) _tile(m, data.names, outline)],
        );
      },
    );
  }

  Widget _tile(
    Map<String, dynamic> m,
    Map<String, String> names,
    Color outline,
  ) {
    final status = m['status'] as String;
    final direction = m['direction'] as String;
    final swimmer = m['swimmers'] as Map?;
    final date = formatDate(DateTime.parse(m['effective_date'] as String));
    final what = switch (direction) {
      'joined' => 'Joined ${_groupName(m['to_group_id'])}',
      'left_club' => 'Left the club (was in ${_groupName(m['from_group_id'])})',
      _ =>
        '${directionLabel(direction)}: ${_groupName(m['from_group_id'])}'
            ' to ${_groupName(m['to_group_id'])}',
    };
    final lines = <String>[
      if (widget.swimmerId == null && swimmer != null)
        '${swimmer['first_name']} ${swimmer['last_name']}',
      switch (status) {
        'scheduled' => 'Scheduled for $date',
        'cancelled' => 'Cancelled (was for $date)',
        _ => date,
      },
      if (m['reason'] != null)
        'Reason: ${m['reason']}${m['share_reason'] == true ? ' (shared with family)' : ''}',
      if (names[m['moved_by']]?.isNotEmpty == true)
        'By ${names[m['moved_by']]}',
    ];
    final icon = switch (direction) {
      'up' => Icons.arrow_upward,
      'down' => Icons.arrow_downward,
      'joined' => Icons.login,
      'left_club' => Icons.logout,
      _ => Icons.swap_horiz,
    };
    return ListTile(
      leading: Icon(icon, color: status == 'cancelled' ? outline : null),
      title: Text(
        what,
        style: status == 'cancelled'
            ? TextStyle(color: outline, decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
      trailing: status == 'scheduled' && widget.canCancel
          ? TextButton(onPressed: () => _cancel(m), child: const Text('Cancel'))
          : null,
    );
  }
}

class _Loaded {
  _Loaded(this.rows, this.names);
  final List<Map<String, dynamic>> rows;
  final Map<String, String> names;
}
