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
