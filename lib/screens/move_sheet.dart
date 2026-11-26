import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Opens the "Move swimmers" panel for one or several swimmers who are all
/// in [from] (null = Unassigned). Returns true if a move was saved.
Future<bool> showMoveSheet(
  BuildContext context, {
  required List<Swimmer> swimmers,
  required Group? from,
  required List<Group> groups,
  VoidCallback? onUndone,
}) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveSheet(
      swimmers: swimmers,
      from: from,
      groups: groups,
      onUndone: onUndone,
    ),
  );
  return moved == true;
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({
    required this.swimmers,
    required this.from,
    required this.groups,
    this.onUndone,
  });
  final VoidCallback? onUndone;
  final List<Swimmer> swimmers;
  final Group? from;
  final List<Group> groups;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  Group? _to;
  DateTime _starting = DateTime.now();
  final _reason = TextEditingController();
  bool _shareReason = false;
  bool _notify = true;
  bool _busy = false;

  late final List<Group> _up = widget.from == null
      ? []
      : groupsOneUp(widget.from!, widget.groups);
  late final List<Group> _down = widget.from == null
      ? []
      : groupsOneDown(widget.from!, widget.groups);
  late final List<Group> _others = sortGroups(widget.groups)
      .where((g) => g.id != widget.from?.id)
      .toList();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _who => widget.swimmers.length == 1
      ? widget.swimmers.first.fullName
      : '${widget.swimmers.length} swimmers';

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _starting,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Move starts on',
    );
    if (picked != null) setState(() => _starting = picked);
  }

  Future<void> _confirm() async {
    final to = _to;
    if (to == null) return;
    setState(() => _busy = true);
    final ids = [for (final s in widget.swimmers) s.id];
    final fromId = widget.from?.id;
    final scheduled = !_isToday(_starting);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final onUndone = widget.onUndone;
    // Undo moves everyone straight back. Only offered for a move that
    // happened now, out of a real group (Unassigned can't be moved back to).
    final undo = (!scheduled && fromId != null)
        ? SnackBarAction(
            label: 'Undo',
            onPressed: () => db
                .rpc(
                  'move_swimmers',
                  params: {
                    'p_swimmer_ids': ids,
                    'p_to_group_id': fromId,
                    'p_reason': 'Undo',
                    'p_notify': false,
                    'p_expected_from_group_ids': [for (final _ in ids) to.id],
                  },
                )
                .then(
                  (_) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Move undone.')),
                    );
                    onUndone?.call();
                  },
                  onError: (Object e) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not undo. Move them back by hand.',
                        ),
                      ),
                    );
                  },
                ),
          )
        : null;
    final ok = await runAction(
      context,
      () => db.rpc(
        'move_swimmers',
        params: {
          'p_swimmer_ids': ids,
          'p_to_group_id': to.id,
          'p_effective_date': dbDate(_starting),
          'p_reason': _reason.text.trim(),
          'p_share_reason': _shareReason,
          'p_notify': _notify,
          // Protects against two coaches moving the same swimmer at once.
          'p_expected_from_group_ids': [for (final _ in ids) fromId],
        },
      ),
      done: scheduled
          ? '$_who will move to ${to.name} on ${formatDate(_starting)}.'
          : widget.from == null
          ? '$_who added to ${to.name}.'
          : '$_who moved from ${widget.from!.name} to ${to.name}.',
      undo: undo,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop(true);
    } else {
      setState(() => _busy = false);
    }
  }

  Widget _choice(String label, Group g, IconData icon) {
    final selected = _to?.id == g.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: selected
          ? FilledButton.icon(
              onPressed: () => setState(() => _to = null),
              icon: const Icon(Icons.check),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: () => setState(() => _to = g),
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherSelected =
        _to != null && !_up.contains(_to) && !_down.contains(_to);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Move $_who', style: Theme.of(context).textTheme.titleLarge),
            Text(
              widget.from == null
                  ? 'Now: no group (Unassigned)'
                  : 'Now in: ${widget.from!.name} (level ${widget.from!.level})',
            ),
            const SizedBox(height: 16),
            for (final g in _up)
              _choice('Move up to ${g.name}', g, Icons.arrow_upward),
            for (final g in _down)
              _choice('Move down to ${g.name}', g, Icons.arrow_downward),
            DropdownButtonFormField<String>(
              // Rebuilds the box when an up/down button is picked instead.
              key: ValueKey(otherSelected ? _to!.id : 'none'),
              initialValue: otherSelected ? _to!.id : null,
              decoration: InputDecoration(
                labelText: widget.from == null ? 'Put in group' : 'Move to...',
              ),
              items: [
                for (final g in _others)
                  DropdownMenuItem(
                    value: g.id,
                    child: Text('${g.name} (level ${g.level})'),
                  ),
              ],
              onChanged: (id) =>
                  setState(() => _to = _others.firstWhere((g) => g.id == id)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text(
                _isToday(_starting)
                    ? 'Starting today, ${formatDate(_starting)}'
                    : 'Starting ${formatDate(_starting)} (scheduled)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: InputDecoration(
                labelText: widget.swimmers.length == 1
                    ? 'Reason (optional)'
                    : 'Reason for everyone (optional)',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _shareReason,
              onChanged: (v) => setState(() => _shareReason = v ?? false),
              title: const Text('Share reason with family'),
              subtitle: const Text('Otherwise only coaches see it.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _notify,
              onChanged: (v) => setState(() => _notify = v ?? true),
              title: const Text('Notify swimmer and parents'),
              subtitle: const Text(
                'Push notifications arrive in a later '
                'version; this choice is saved now.',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _to == null || _busy ? null : _confirm,
              child: Text(_to == null ? 'Choose a group' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}
