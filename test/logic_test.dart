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

  test('session times are shown the way coaches write them', () {
    expect(parseDbTime('16:30:00'), 990);
    expect(dbTime(390), '06:30');
    expect(formatTime(0), '12:00 AM');
    expect(formatTime(12 * 60 + 5), '12:05 PM');
    expect(timeRange(16 * 60 + 30, 19 * 60), '4:30-7:00 PM');
    expect(timeRange(11 * 60, 13 * 60), '11:00 AM-1:00 PM');
  });

  test('days are written short, Monday first', () {
    expect(weekdayShort(1), 'Mon');
    expect(weekdayShort(7), 'Sun');
    expect(formatDayShort(DateTime(2026, 11, 27)), 'Fri 27 Nov');
  });

  // ---------- Attendance ----------

  test(
    'attendance scoring: present 1, late/early-up/DNF half, excused left out',
    () {
      final s = AttendanceSummary([
        'present',
        'present',
        'late',
        'early_up',
        'dnf',
        'absent',
        'excused',
      ]);
      expect(s.counted, 6);
      expect(s.points, 3.5);
      expect(s.percent, 58);
      expect(s.count('excused'), 1);
      expect(AttendanceSummary(['excused']).percent, isNull);
      expect(AttendanceSummary(['present', 'late']).percent, 75);
    },
  );

  test('coaches can mark for 7 days, then only the head coach', () {
    final today = DateTime(2026, 11, 26);
    bool can(DateTime d, {bool head = false}) =>
        canMarkAttendance(d, isHeadCoach: head, today: today);
    expect(can(DateTime(2026, 11, 26)), isTrue);
    expect(can(DateTime(2026, 11, 19)), isTrue);
    expect(can(DateTime(2026, 11, 18)), isFalse);
    expect(can(DateTime(2026, 11, 18), head: true), isTrue);
    expect(can(DateTime(2026, 11, 27), head: true), isFalse);
  });

  test(
    'needs attendance: started, not cancelled, not marked, has swimmers',
    () {
      SessionOverview s(
        String id,
        DateTime date,
        int start, {
        int marked = 0,
        int swimmers = 10,
        bool cancelled = false,
      }) => SessionOverview(
        sessionId: id,
        groupId: 'g',
        groupName: 'Gold',
        groupLevel: 3,
        date: date,
        start: start,
        end: start + 60,
        marked: marked,
        swimmers: swimmers,
        cancelled: cancelled,
      );
      final now = DateTime(2026, 11, 26, 9, 0);
      final list = needsAttendance([
        s('yesterday', DateTime(2026, 11, 25), 990),
        s('this-morning', DateTime(2026, 11, 26), 360),
        s('this-evening', DateTime(2026, 11, 26), 990),
        s('done', DateTime(2026, 11, 24), 990, marked: 8),
        s('cancelled', DateTime(2026, 11, 23), 990, cancelled: true),
        s('empty-group', DateTime(2026, 11, 23), 990, swimmers: 0),
      ], now: now);
      expect(list.map((x) => x.sessionId), ['this-morning', 'yesterday']);
    },
  );

  test('attendance letters and names', () {
    expect(attendanceStatuses.map(attendanceLetter).join(), 'PALUDE');
    expect(attendanceLabel('early_up'), 'Early-Up');
    expect(excuseReasons.map(excuseLabel), ['Medical', 'School', 'Family']);
  });

  ClubEvent ev(DateTime a, DateTime b, {int? start, int? end, DateTime? up}) =>
      ClubEvent(
        id: 'e',
        title: 'Champs',
        kind: 'meet',
        startDate: a,
        endDate: b,
        start: start,
        end: end,
        updatedAt: up,
      );

  test('event dates and times are written for people', () {
    final sat = DateTime(2026, 12, 12);
    final sun = DateTime(2026, 12, 13);
    expect(eventWhen(ev(sat, sat)), 'Sat 12 Dec');
    expect(eventWhen(ev(sat, sun)), 'Sat 12 - Sun 13 Dec');
    expect(
      eventWhen(ev(DateTime(2026, 12, 31), DateTime(2027, 1, 1))),
      'Thu 31 Dec - Fri 1 Jan',
    );
    expect(
      eventWhen(ev(sat, sat, start: 7 * 60, end: 18 * 60)),
      'Sat 12 Dec, 7:00 AM-6:00 PM',
    );
    expect(
      eventWhen(ev(sat, sun, start: 7 * 60, end: 18 * 60)),
      'Sat 12 - Sun 13 Dec, from 7:00 AM',
    );
  });

  test('an edited event shows as updated for 3 days', () {
    final now = DateTime(2026, 12, 10, 12);
    final day = DateTime(2026, 12, 20);
    expect(recentlyUpdated(ev(day, day), now: now), isFalse);
    expect(
      recentlyUpdated(ev(day, day, up: DateTime(2026, 12, 8, 12)), now: now),
      isTrue,
    );
    expect(
      recentlyUpdated(ev(day, day, up: DateTime(2026, 12, 7, 11)), now: now),
      isFalse,
    );
  });

  test('event labels and map links', () {
    expect(eventKinds.map(eventKindLabel), ['Meet', 'Social', 'Other']);
    expect(courseLabel('lcm'), 'LCM (50 m)');
    expect(
      mapsLink('Rizal Memorial Pool').toString(),
      'https://www.google.com/maps/search/?api=1&query=Rizal+Memorial+Pool',
    );
  });

  test('events read from the coach table and from swimmer_events', () {
    final coach = ClubEvent.fromRow({
      'id': 'e1',
      'title': 'Party',
      'kind': 'social',
      'start_date': '2026-12-20',
      'end_date': '2026-12-20',
      'start_time': '18:00:00',
      'end_time': '21:00:00',
      'whole_club': false,
      'event_groups': [
        {'group_id': 'g1'},
      ],
      'rest_days': [
        {'id': 'r1'},
      ],
    });
    expect(coach.start, 18 * 60);
    expect(coach.wholeClub, isFalse);
    expect(coach.groupIds, ['g1']);
    expect(coach.cancelsTraining, isTrue);
    final family = ClubEvent.fromRow({
      'event_id': 'e2',
      'title': 'Champs',
      'kind': 'meet',
      'start_date': '2026-12-12',
      'end_date': '2026-12-13',
      'course': 'lcm',
    });
    expect(family.id, 'e2');
    expect(family.allDay, isTrue);
    expect(family.cancelsTraining, isFalse);
  });
}
