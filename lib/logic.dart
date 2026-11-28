// Small rules used by the screens, kept here (away from the screens) so the
// automatic tests in test/logic_test.dart can check them.

import 'models.dart';

/// Age in whole years on [on] (today if left out).
int ageOn(DateTime birth, [DateTime? on]) {
  final d = on ?? DateTime.now();
  var age = d.year - birth.year;
  if (d.month < birth.month || (d.month == birth.month && d.day < birth.day)) {
    age--;
  }
  return age;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A date written like "26 Nov 2026".
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// A date the way the database wants it: "2026-11-26".
String dbDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// Active groups sorted highest level first, then by name.
List<Group> sortGroups(Iterable<Group> groups) {
  final list = groups.where((g) => !g.archived).toList()
    ..sort((a, b) {
      final byLevel = b.level.compareTo(a.level);
      return byLevel != 0
          ? byLevel
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return list;
}

/// The group(s) one step up from [from]: the active groups at the next
/// higher level. Empty for the top group. Two groups may share a level,
/// so this can return more than one.
List<Group> groupsOneUp(Group from, Iterable<Group> all) {
  final higher = all.where((g) => !g.archived && g.level > from.level);
  if (higher.isEmpty) return [];
  final next = higher.map((g) => g.level).reduce((a, b) => a < b ? a : b);
  return sortGroups(higher.where((g) => g.level == next));
}

/// The group(s) one step down from [from]. Empty for the bottom group.
List<Group> groupsOneDown(Group from, Iterable<Group> all) {
  final lower = all.where((g) => !g.archived && g.level < from.level);
  if (lower.isEmpty) return [];
  final next = lower.map((g) => g.level).reduce((a, b) => a > b ? a : b);
  return sortGroups(lower.where((g) => g.level == next));
}

/// Plain words for a move direction from the database.
String directionLabel(String direction) => switch (direction) {
  'joined' => 'Joined',
  'up' => 'Moved up',
  'down' => 'Moved down',
  'sideways' => 'Moved',
  'left_club' => 'Left the club',
  _ => direction,
};

// ---------- Training schedules ----------

/// Day names, Monday first (the database uses 1 = Monday ... 7 = Sunday).
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "Mon", "Tue"... for weekday 1 to 7.
String weekdayShort(int weekday) => weekdayNames[weekday - 1].substring(0, 3);

/// A database time like "16:30:00" as minutes after midnight (990).
int parseDbTime(String text) {
  final parts = text.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Minutes after midnight the way the database wants them: "16:30".
String dbTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// Minutes after midnight for people: "4:30 PM".
String formatTime(int minutes) {
  final h = minutes ~/ 60;
  final m = (minutes % 60).toString().padLeft(2, '0');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m ${h < 12 ? 'AM' : 'PM'}';
}

/// "4:30-7:00 PM", or "11:00 AM-1:00 PM" when it crosses noon.
String timeRange(int start, int end) {
  final a = formatTime(start);
  final b = formatTime(end);
  if (a.substring(a.length - 2) == b.substring(b.length - 2)) {
    return '${a.substring(0, a.length - 3)}-$b';
  }
  return '$a-$b';
}

/// A date written like "Thu 27 Nov".
String formatDayShort(DateTime d) =>
    '${weekdayShort(d.weekday)} ${d.day} ${_months[d.month - 1]}';

/// Today's date with no time of day.
DateTime dateOnly([DateTime? d]) {
  final x = d ?? DateTime.now();
  return DateTime(x.year, x.month, x.day);
}

// ---------- Attendance ----------

/// The attendance marks, in the order the coach screen shows them, with
/// the one-letter button and the full name.
const attendanceStatuses = [
  'present',
  'absent',
  'late',
  'early_up',
  'dnf',
  'excused',
];

/// "P", "A", "L", "U", "D", "E" for the coach's buttons.
String attendanceLetter(String status) => switch (status) {
  'present' => 'P',
  'absent' => 'A',
  'late' => 'L',
  'early_up' => 'U',
  'dnf' => 'D',
  'excused' => 'E',
  _ => '?',
};

/// "Present", "Early-Up"... for people.
String attendanceLabel(String status) => switch (status) {
  'present' => 'Present',
  'absent' => 'Absent',
  'late' => 'Late',
  'early_up' => 'Early-Up',
  'dnf' => 'Did not finish',
  'excused' => 'Excused',
  _ => status,
};

/// The reasons for an Excused mark.
const excuseReasons = ['medical', 'school', 'family'];

/// "Medical", "School", "Family".
String excuseLabel(String reason) => switch (reason) {
  'medical' => 'Medical',
  'school' => 'School',
  'family' => 'Family',
  _ => reason,
};

/// Points for one mark: Present 1, Late / Early-Up / DNF half, Absent 0.
/// Null for Excused, which is left out of the percentage.
double? attendancePoints(String status) => switch (status) {
  'present' => 1,
  'late' || 'early_up' || 'dnf' => 0.5,
  'absent' => 0,
  _ => null,
};

/// Totals for a list of marks.
class AttendanceSummary {
  AttendanceSummary(Iterable<String> statuses) {
    for (final s in statuses) {
      counts[s] = (counts[s] ?? 0) + 1;
      final p = attendancePoints(s);
      if (p != null) {
        points += p;
        counted++;
      }
    }
  }

  final Map<String, int> counts = {};
  double points = 0;
  int counted = 0; // marks that count (all but Excused)

  int count(String status) => counts[status] ?? 0;

  /// The attendance percentage, rounded, or null when nothing counts yet.
  int? get percent => counted == 0 ? null : (points * 100 / counted).round();
}

/// Can a coach mark (or change) a session on [sessionDate] today?
/// Only on or after the day, and for 7 days after it unless head coach.
bool canMarkAttendance(
  DateTime sessionDate, {
  required bool isHeadCoach,
  DateTime? today,
}) {
  final t = dateOnly(today);
  final d = dateOnly(sessionDate);
  if (d.isAfter(t)) return false;
  return isHeadCoach || !d.isBefore(t.subtract(const Duration(days: 7)));
}

/// The sessions still waiting for attendance: not cancelled, with
/// swimmers, nobody marked, and already started (by [now]). Newest first.
List<SessionOverview> needsAttendance(
  Iterable<SessionOverview> sessions, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = dateOnly(n);
  final minutes = n.hour * 60 + n.minute;
  final list =
      sessions.where((s) {
        if (s.cancelled || s.isMarked || s.swimmers == 0) return false;
        final d = dateOnly(s.date);
        return d.isBefore(today) || (d == today && s.start <= minutes);
      }).toList()..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.start.compareTo(a.start);
      });
  return list;
}

// ---------- Events ----------

/// The event types, in the order the form shows them.
const eventKinds = ['meet', 'social', 'other'];

/// "Meet", "Social", "Other".
String eventKindLabel(String kind) => switch (kind) {
  'meet' => 'Meet',
  'social' => 'Social',
  'other' => 'Other',
  _ => kind,
};

/// "LCM (50 m)" or "SCM (25 m)".
String courseLabel(String course) => switch (course) {
  'lcm' => 'LCM (50 m)',
  'scm' => 'SCM (25 m)',
  _ => course,
};

/// When an event is, for people: "Sat 13 Dec", "Sat 13 - Sun 14 Dec",
/// "Sat 13 Dec, 7:00 AM-6:00 PM" or across months "Wed 31 Dec - Thu 1 Jan".
String eventWhen(ClubEvent e) {
  final a = e.startDate;
  final b = e.endDate;
  String days;
  if (a == b) {
    days = formatDayShort(a);
  } else if (a.month == b.month && a.year == b.year) {
    days = '${weekdayShort(a.weekday)} ${a.day} - ${formatDayShort(b)}';
  } else {
    days = '${formatDayShort(a)} - ${formatDayShort(b)}';
  }
  if (e.allDay) return days;
  if (a == b) return '$days, ${timeRange(e.start!, e.end!)}';
  return '$days, from ${formatTime(e.start!)}';
}

/// True when the event was changed in the last 3 days, so families see
/// an "Updated" tag on it.
bool recentlyUpdated(ClubEvent e, {DateTime? now}) {
  final u = e.updatedAt;
  if (u == null) return false;
  return (now ?? DateTime.now()).difference(u) < const Duration(days: 3);
}

/// A Google Maps search link for a place, so families can get directions.
Uri mapsLink(String place) =>
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': place});

// ---------- Swim times and personal bests ----------

/// The courses, in the order the screens show them.
const courses = ['lcm', 'scm'];

/// "LCM 50 m" / "SCM 25 m" for the course toggles.
String courseShort(String course) => switch (course) {
  'lcm' => 'LCM 50 m',
  'scm' => 'SCM 25 m',
  _ => course,
};

/// The events a time can be entered for in [course], in the usual order:
/// Free 50 to 1500; Back, Breast and Fly 50 to 200; IM 100 (SCM only),
/// 200 and 400. The database checks the same list.
List<SwimEvent> swimEvents(String course) => [
  for (final d in const [50, 100, 200, 400, 800, 1500]) SwimEvent('free', d),
  for (final s in const ['back', 'breast', 'fly'])
    for (final d in const [50, 100, 200]) SwimEvent(s, d),
  if (course == 'scm') const SwimEvent('im', 100),
  const SwimEvent('im', 200),
  const SwimEvent('im', 400),
];

/// A time in hundredths for people: 2984 -> "29.84", 6542 -> "1:05.42",
/// 96233 -> "16:02.33".
String formatSwimTime(int cs) {
  final minutes = cs ~/ 6000;
  final seconds = (cs % 6000) ~/ 100;
  final hundredths = (cs % 100).toString().padLeft(2, '0');
  if (minutes == 0) return '$seconds.$hundredths';
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$hundredths';
}

/// A difference between two times: "-0.68", "+1.20".
String formatTimeDiff(int cs) =>
    '${cs < 0 ? '-' : '+'}${formatSwimTime(cs.abs())}';

/// A time the coach typed, in hundredths, or null if it can't be read.
/// Takes "1:05.42", "65.42", "29.8" (tenths), "1:05" or "1.05.42".
int? parseSwimTime(String text) {
  var t = text.trim().replaceAll(',', '.').replaceAll(' ', '');
  var minutes = 0;
  // "1.05.42" means 1:05.42.
  if (!t.contains(':') && '.'.allMatches(t).length == 2) {
    t = t.replaceFirst('.', ':');
  }
  if (t.contains(':')) {
    final parts = t.split(':');
    if (parts.length != 2 || !RegExp(r'^\d{1,2}$').hasMatch(parts[0])) {
      return null;
    }
    minutes = int.parse(parts[0]);
    t = parts[1];
    if (!RegExp(r'^\d{2}(\.\d{1,2})?$').hasMatch(t)) return null;
  }
  final m = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final seconds = int.parse(m.group(1)!);
  if (minutes > 0 && seconds >= 60) return null;
  final fraction = (m.group(2) ?? '0').padRight(2, '0');
  final cs = (minutes * 60 + seconds) * 100 + int.parse(fraction);
  return cs > 0 && cs < 360000 ? cs : null;
}

/// The fastest swim (earliest if tied) per event in [course]: the
/// swimmer's personal bests, in the usual event order.
List<SwimResult> personalBests(Iterable<SwimResult> results, String course) {
  final best = <SwimEvent, SwimResult>{};
  for (final r in results.where((r) => r.course == course)) {
    final b = best[r.event];
    if (b == null ||
        r.timeCs < b.timeCs ||
        (r.timeCs == b.timeCs && r.date.isBefore(b.date))) {
      best[r.event] = r;
    }
  }
  return [
    for (final e in swimEvents(course))
      if (best[e] != null) best[e]!,
  ];
}

/// Every swim in one event and course, fastest first.
List<SwimResult> swimsIn(
  Iterable<SwimResult> results,
  String course,
  SwimEvent event,
) =>
    results.where((r) => r.course == course && r.event == event).toList()
      ..sort((a, b) {
        final byTime = a.timeCs.compareTo(b.timeCs);
        return byTime != 0 ? byTime : a.date.compareTo(b.date);
      });

/// True when a PB was swum in the last 30 days, so it shows as NEW.
bool isNewPb(SwimResult r, {DateTime? today}) =>
    !dateOnly(r.date)
        .isBefore(dateOnly(today).subtract(const Duration(days: 30)));

/// The age groups the Team bests filter offers: label and ages (to is
/// null for "and over").
const ageGroups = <(String, int, int?)>[
  ('10 & under', 0, 10),
  ('11-12', 11, 12),
  ('13-14', 13, 14),
  ('15-17', 15, 17),
  ('18 & over', 18, null),
];

/// One line of the Team bests ranking.
class TeamBest {
  TeamBest(this.swimmer, this.best);
  final Swimmer swimmer;
  final SwimResult best;
}

/// Each swimmer's best in one event, fastest first. Only swimmers in
/// [swimmers] (already filtered by group, gender and age) are ranked.
List<TeamBest> teamRanking(
  Iterable<SwimResult> results,
  Iterable<Swimmer> swimmers,
) {
  final byId = {for (final s in swimmers) s.id: s};
  final best = <String, SwimResult>{};
  for (final r in results) {
    if (!byId.containsKey(r.swimmerId)) continue;
    final b = best[r.swimmerId];
    if (b == null ||
        r.timeCs < b.timeCs ||
        (r.timeCs == b.timeCs && r.date.isBefore(b.date))) {
      best[r.swimmerId] = r;
    }
  }
  final list = [for (final e in best.entries) TeamBest(byId[e.key]!, e.value)]
    ..sort((a, b) {
      final byTime = a.best.timeCs.compareTo(b.best.timeCs);
      return byTime != 0 ? byTime : a.best.date.compareTo(b.best.date);
    });
  return list;
}
