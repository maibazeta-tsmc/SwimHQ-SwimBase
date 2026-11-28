import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/attendance_dashboard.dart';
import '../widgets/common.dart';
import 'attendance_screen.dart';

/// Loads the club's sessions between two dates with their attendance.
Future<List<SessionOverview>> loadOverview(
  String clubId,
  DateTime from,
  DateTime to,
) async {
  final rows = await db.rpc(
    'club_attendance_overview',
    params: {'p_club_id': clubId, 'p_from': dbDate(from), 'p_to': dbDate(to)},
  );
  return [for (final r in rows as List) SessionOverview.fromRow(r)];
}

/// Opens the attendance screen. Returns true if something was saved.
Future<bool> openAttendance(
  BuildContext context,
  Membership club,
  SessionOverview session,
) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AttendanceScreen(club: club, session: session),
    ),
  );
  return saved == true;
}

/// One session as a list row, with its attendance status on the right.
class SessionAttendanceTile extends StatelessWidget {
  const SessionAttendanceTile({
    super.key,
    required this.session,
    required this.onTap,
    this.showDate = false,
  });
  final SessionOverview session;
  final VoidCallback onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final started =
        dateOnly(s.date).isBefore(dateOnly(now)) ||
        (dateOnly(s.date) == dateOnly(now) &&
            s.start <= now.hour * 60 + now.minute);
    final String status;
    Color? colour;
    if (s.cancelled) {
      status = s.note == null ? 'Cancelled' : 'Cancelled: ${s.note}';
      colour = scheme.error;
    } else if (s.isMarked) {
      status = 'Taken  ·  ${s.marked} marked';
      colour = scheme.primary;
    } else if (s.swimmers == 0) {
      status = 'No swimmers';
    } else if (!started) {
      status = 'Upcoming';
    } else {
      status = 'Not taken';
      colour = scheme.error;
    }
    return ListTile(
      leading: LevelBadge(level: s.groupLevel, colour: s.groupColour),
      title: Text(
        [
          s.groupName,
          if (showDate) formatDayShort(s.date),
          timeRange(s.start, s.end),
        ].join('   '),
        style: s.cancelled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        [if (s.label != null) s.label!, status].join('  ·  '),
        style: TextStyle(color: colour),
      ),
      trailing: s.cancelled ? null : const Icon(Icons.chevron_right),
      onTap: s.cancelled ? null : onTap,
    );
  }
}

/// The coach's home tab: the attendance summary, which sessions still
/// need attendance, and today's sessions for every group.
class TodayTab extends StatefulWidget {
  const TodayTab({super.key, required this.club});
  final Membership club;

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  late Future<List<SessionOverview>> _sessions = _load();
  int _refreshCount = 0;

  Future<List<SessionOverview>> _load() {
    final today = dateOnly();
    return loadOverview(
      widget.club.clubId,
      today.subtract(const Duration(days: 7)),
      today,
    );
  }

  void _refresh() => setState(() {
    _sessions = _load();
    _refreshCount++;
  });

  Future<void> _open(SessionOverview s) async {
    if (await openAttendance(context, widget.club, s) && mounted) _refresh();
  }

  Future<void> _otherDay() async {
    final today = dateOnly();
    final day = await showDatePicker(
      context: context,
      initialDate: today.subtract(const Duration(days: 1)),
      firstDate: DateTime(today.year - 1, 1, 1),
      lastDate: today,
      helpText: 'Attendance for which day?',
    );
    if (day == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayAttendanceScreen(club: widget.club, day: day),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SessionOverview>>(
      future: _sessions,
      builder: (context, snapshot) {
        final sessions = snapshot.data;
        if (sessions == null) {
          return LoadState(error: snapshot.error, onRetry: _refresh);
        }
        final text = Theme.of(context).textTheme;
        final today = dateOnly();
        final needs = needsAttendance(sessions);
        final todays = sessions.where((s) => dateOnly(s.date) == today);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              AttendanceDashboard(
                club: widget.club,
                refreshCount: _refreshCount,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Needs attendance (${needs.length})',
                  style: text.titleMedium,
                ),
              ),
              if (needs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('All caught up for the last 7 days.'),
                ),
              for (final s in needs)
                SessionAttendanceTile(
                  session: s,
                  showDate: true,
                  onTap: () => _open(s),
                ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Today, ${formatDayShort(today)}',
                  style: text.titleMedium,
                ),
              ),
              if (todays.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('No training today.'),
                ),
              for (final s in todays)
                SessionAttendanceTile(session: s, onTap: () => _open(s)),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _otherDay,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Attendance for another day'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Every group's sessions on one chosen day, to take or check attendance.
class DayAttendanceScreen extends StatefulWidget {
  const DayAttendanceScreen({super.key, required this.club, required this.day});
  final Membership club;
  final DateTime day;

  @override
  State<DayAttendanceScreen> createState() => _DayAttendanceScreenState();
}

class _DayAttendanceScreenState extends State<DayAttendanceScreen> {
  late Future<List<SessionOverview>> _sessions = _load();

  Future<List<SessionOverview>> _load() =>
      loadOverview(widget.club.clubId, widget.day, widget.day);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(formatDayShort(widget.day))),
      body: FutureBuilder<List<SessionOverview>>(
        future: _sessions,
        builder: (context, snapshot) {
          final sessions = snapshot.data;
          if (sessions == null) {
            return LoadState(
              error: snapshot.error,
              onRetry: () => setState(() => _sessions = _load()),
            );
          }
          if (sessions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No training on this day.'),
            );
          }
          return ListView(
            children: [
              for (final s in sessions)
                SessionAttendanceTile(
                  session: s,
                  onTap: () async {
                    if (await openAttendance(context, widget.club, s) &&
                        mounted) {
                      setState(() => _sessions = _load());
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
