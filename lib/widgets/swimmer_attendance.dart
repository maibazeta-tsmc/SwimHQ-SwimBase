import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import 'common.dart';

/// One swimmer's attendance this season (1 Jan to today): the percentage,
/// the count of each mark, and the most recent sessions. Families see
/// this for themselves or their children; coaches also see their notes.
class SwimmerAttendance extends StatefulWidget {
  const SwimmerAttendance({super.key, required this.swimmerId});
  final String swimmerId;

  @override
  State<SwimmerAttendance> createState() => _SwimmerAttendanceState();
}

class _SwimmerAttendanceState extends State<SwimmerAttendance> {
  late Future<List<AttendanceRecord>> _records = _load();
  bool _showAll = false;

  Future<List<AttendanceRecord>> _load() async {
    final today = dateOnly();
    final rows = await db.rpc(
      'swimmer_attendance',
      params: {
        'p_swimmer_id': widget.swimmerId,
        'p_from': dbDate(DateTime(today.year, 1, 1)),
        'p_to': dbDate(today),
      },
    );
    return [for (final r in rows as List) AttendanceRecord.fromRow(r)];
  }

  @override
  void didUpdateWidget(SwimmerAttendance old) {
    super.didUpdateWidget(old);
    if (old.swimmerId != widget.swimmerId) {
      _records = _load();
      _showAll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AttendanceRecord>>(
      future: _records,
      builder: (context, snapshot) {
        final records = snapshot.data;
        if (records == null) {
          return LoadState(
            error: snapshot.error,
            onRetry: () => setState(() => _records = _load()),
          );
        }
        if (records.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No attendance taken yet this season.'),
          );
        }
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final summary = AttendanceSummary(records.map((r) => r.status));
        final shown = _showAll ? records : records.take(10).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    summary.percent == null ? '–' : '${summary.percent}%',
                    style: text.displaySmall?.copyWith(color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'this season\n'
                      '${records.length} sessions marked',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final st in attendanceStatuses)
                    if (summary.count(st) > 0)
                      Chip(
                        label: Text(
                          '${attendanceLabel(st)} ${summary.count(st)}',
                        ),
                      ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                'Late, Early-Up and Did not finish count as half. '
                'Excused sessions are not counted.',
              ),
            ),
            for (final r in shown)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: _colour(r.status, scheme),
                  foregroundColor: scheme.surface,
                  child: Text(attendanceLetter(r.status)),
                ),
                title: Text(
                  '${formatDayShort(r.date)}   ${timeRange(r.start, r.end)}',
                ),
                subtitle: Text(
                  [
                    r.status == 'excused' && r.excuseReason != null
                        ? 'Excused (${excuseLabel(r.excuseReason!)})'
                        : attendanceLabel(r.status),
                    r.groupName,
                    if (r.note != null) 'Note: ${r.note}',
                  ].join('  ·  '),
                ),
              ),
            if (records.length > shown.length)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton(
                  onPressed: () => setState(() => _showAll = true),
                  child: Text('Show all ${records.length}'),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _colour(String status, ColorScheme scheme) => switch (status) {
    'present' => Colors.green.shade700,
    'absent' => scheme.error,
    'excused' => Colors.blueGrey,
    _ => Colors.orange.shade800,
  };
}
