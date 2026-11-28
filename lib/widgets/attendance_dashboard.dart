import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../screens/swimmer_screen.dart';
import 'common.dart';

/// The coach's attendance summary at the top of the Today tab: the club's
/// attendance rate for this week, month or season, each group's rate, and
/// the swimmers with the lowest attendance.
class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({
    super.key,
    required this.club,
    this.refreshCount = 0,
  });
  final Membership club;

  /// Bump this to load the numbers again (e.g. after attendance is saved).
  final int refreshCount;

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> {
  String _period = 'month';
  late Future<AttendanceDashboardData> _data = _load();

  Future<AttendanceDashboardData> _load() async {
    final today = dateOnly();
    final rows = await db.rpc(
      'club_attendance_summary',
      params: {
        'p_club_id': widget.club.clubId,
        'p_from': dbDate(dashboardPeriodStart(_period, today)),
        'p_to': dbDate(today),
      },
    );
    return AttendanceDashboardData([
      for (final r in rows as List) AttendanceCountRow.fromRow(r),
    ]);
  }

  void _reload() => setState(() => _data = _load());

  @override
  void didUpdateWidget(AttendanceDashboard old) {
    super.didUpdateWidget(old);
    if (old.refreshCount != widget.refreshCount ||
        old.club.clubId != widget.club.clubId) {
      _data = _load();
    }
  }

  void _openSwimmer(AttendanceRate s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwimmerScreen(club: widget.club, swimmerId: s.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Attendance summary', style: text.titleMedium),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final p in dashboardPeriods)
                    ButtonSegment(
                      value: p,
                      label: Text(dashboardPeriodLabel(p).split(' ').last),
                    ),
                ],
                selected: {_period},
                onSelectionChanged: (s) {
                  _period = s.first;
                  _reload();
                },
              ),
            ),
            FutureBuilder<AttendanceDashboardData>(
              future: _data,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null ||
                    snapshot.connectionState == ConnectionState.waiting) {
                  return LoadState(error: snapshot.error, onRetry: _reload);
                }
                return _body(context, data);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AttendanceDashboardData data) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          'No attendance taken ${dashboardPeriodLabel(_period).toLowerCase()} '
          'yet.',
        ),
      );
    }
    final club = data.club;
    final lowest = data.swimmers.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                club.percent == null ? '–' : '${club.percent}%',
                style: text.displaySmall?.copyWith(
                  color: _colour(club.percent, scheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'whole club, ${dashboardPeriodLabel(_period).toLowerCase()}\n'
                  '${_marks(club)}',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('By group', style: text.titleSmall),
        ),
        for (final g in data.groups)
          _RateTile(
            rate: g,
            subtitle: _marks(g.summary),
            colour: _colour(g.summary.percent, scheme),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Lowest attendance', style: text.titleSmall),
        ),
        if (lowest.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Nobody yet.'),
          ),
        for (final s in lowest) _swimmerTile(s, scheme),
        if (data.swimmers.length > lowest.length)
          SeeAllButton(
            count: data.swimmers.length,
            title: 'Attendance, ${dashboardPeriodLabel(_period).toLowerCase()}',
            page: Column(
              children: [
                for (final s in data.swimmers) _swimmerTile(s, scheme),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Late, Early-Up and Did not finish count as half. Excused '
            'sessions are not counted. Below $lowAttendancePercent% is '
            'shown in red.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _swimmerTile(AttendanceRate s, ColorScheme scheme) => _RateTile(
    rate: s,
    subtitle: [
      if (s.groupName != null) s.groupName!,
      _marks(s.summary),
    ].join('  ·  '),
    colour: _colour(s.summary.percent, scheme),
    onTap: () => _openSwimmer(s),
  );

  /// "12 sessions: 9 present, 2 late, 1 absent".
  static String _marks(AttendanceSummary s) {
    final total = s.counts.values.fold(0, (a, b) => a + b);
    final parts = [
      for (final st in attendanceStatuses)
        if (s.count(st) > 0)
          '${s.count(st)} ${attendanceLabel(st).toLowerCase()}',
    ];
    return '$total ${total == 1 ? 'mark' : 'marks'}: ${parts.join(', ')}';
  }

  static Color? _colour(int? percent, ColorScheme scheme) {
    if (percent == null) return null;
    return percent < lowAttendancePercent
        ? scheme.error
        : Colors.green.shade700;
  }
}

/// One row: badge, name, a bar and the percentage.
class _RateTile extends StatelessWidget {
  const _RateTile({
    required this.rate,
    required this.subtitle,
    this.colour,
    this.onTap,
  });
  final AttendanceRate rate;
  final String subtitle;
  final Color? colour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final percent = rate.summary.percent;
    return ListTile(
      dense: true,
      leading: LevelBadge(level: rate.level, colour: rate.colour),
      title: Text(rate.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: percent == null ? 0 : percent / 100,
            color: colour,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
          Text(subtitle),
        ],
      ),
      trailing: Text(
        percent == null ? '–' : '$percent%',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colour),
      ),
      onTap: onTap,
    );
  }
}
