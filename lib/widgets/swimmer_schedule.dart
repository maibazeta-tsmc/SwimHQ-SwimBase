import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import 'common.dart';

/// One swimmer's training for the next [days] days. It follows the group
/// the swimmer is in on each date, so after a move (or a planned move) it
/// shows the new group's sessions from the move date.
class SwimmerSchedule extends StatefulWidget {
  const SwimmerSchedule({super.key, required this.swimmerId, this.days = 14});
  final String swimmerId;
  final int days;

  @override
  State<SwimmerSchedule> createState() => _SwimmerScheduleState();
}

class _SwimmerScheduleState extends State<SwimmerSchedule> {
  late Future<List<ScheduleEntry>> _entries = _load();

  Future<List<ScheduleEntry>> _load() async {
    final from = dateOnly();
    final rows = await db.rpc(
      'swimmer_schedule',
      params: {
        'p_swimmer_id': widget.swimmerId,
        'p_from': dbDate(from),
        'p_to': dbDate(from.add(Duration(days: widget.days - 1))),
      },
    );
    return [for (final r in rows as List) ScheduleEntry.fromRow(r)];
  }

  @override
  void didUpdateWidget(SwimmerSchedule old) {
    super.didUpdateWidget(old);
    if (old.swimmerId != widget.swimmerId) _entries = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScheduleEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        final entries = snapshot.data;
        if (entries == null) {
          return LoadState(
            error: snapshot.error,
            onRetry: () => setState(() => _entries = _load()),
          );
        }
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No training on the calendar yet.'),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        // Show the group name only when it changes inside the range.
        final manyGroups = entries.map((e) => e.groupId).toSet().length > 1;
        return Column(
          children: [
            for (final e in entries)
              ListTile(
                dense: true,
                leading: Icon(
                  e.isRest
                      ? Icons.beach_access
                      : e.isCancelled
                      ? Icons.event_busy
                      : Icons.pool,
                  color: e.isCancelled ? scheme.error : scheme.primary,
                ),
                title: Text(
                  e.isRest
                      ? '${formatDayShort(e.date)}   ${e.note ?? 'Rest day'}'
                      : '${formatDayShort(e.date)}   '
                            '${timeRange(e.start!, e.end!)}',
                  style: e.isCancelled
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null,
                ),
                subtitle: () {
                  final parts = [
                    if (manyGroups) e.groupName,
                    if (e.label != null) e.label!,
                    if (e.venue != null) e.venue!,
                    if (e.isCancelled)
                      'Cancelled${e.note != null ? ': ${e.note}' : ''}',
                  ];
                  return parts.isEmpty ? null : Text(parts.join('  ·  '));
                }(),
              ),
          ],
        );
      },
    );
  }
}
