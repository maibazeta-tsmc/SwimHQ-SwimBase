import 'package:flutter_test/flutter_test.dart';
import 'package:swimbase/logic.dart';
import 'package:swimbase/models.dart';

Group g(String name, int level, {bool archived = false}) =>
    Group(id: name, name: name, level: level, archived: archived);

void main() {
  test('age counts whole years and waits for the birthday', () {
    final birth = DateTime(2014, 6, 15);
    expect(ageOn(birth, DateTime(2026, 6, 14)), 11);
    expect(ageOn(birth, DateTime(2026, 6, 15)), 12);
    expect(ageOn(birth, DateTime(2026, 12, 31)), 12);
  });

  test('dates are written for people and for the database', () {
    expect(formatDate(DateTime(2026, 11, 26)), '26 Nov 2026');
    expect(dbDate(DateTime(2026, 3, 5)), '2026-03-05');
  });

  final groups = [
    g('Bronze', 1),
    g('Silver A', 2),
    g('Silver B', 2),
    g('Gold', 3),
    g('Senior', 5),
    g('Old', 4, archived: true),
  ];

  test('groups are listed top level first, archived left out', () {
    expect(sortGroups(groups).map((x) => x.name), [
      'Senior',
      'Gold',
      'Silver A',
      'Silver B',
      'Bronze',
    ]);
  });

  test('move up finds the next level, skipping gaps and archived groups', () {
    expect(groupsOneUp(groups[3], groups).map((x) => x.name), ['Senior']);
    expect(groupsOneUp(groups[0], groups).map((x) => x.name), [
      'Silver A',
      'Silver B',
    ]);
    expect(groupsOneUp(groups[4], groups), isEmpty);
  });

  test('move down finds the next level below', () {
    expect(groupsOneDown(groups[3], groups).map((x) => x.name), [
      'Silver A',
      'Silver B',
    ]);
    expect(groupsOneDown(groups[1], groups).map((x) => x.name), ['Bronze']);
    expect(groupsOneDown(groups[0], groups), isEmpty);
  });
}
