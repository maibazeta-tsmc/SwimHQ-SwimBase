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
