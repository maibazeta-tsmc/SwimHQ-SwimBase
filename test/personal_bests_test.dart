import 'package:flutter_test/flutter_test.dart';
import 'package:swimbase/logic.dart';
import 'package:swimbase/models.dart';

SwimResult swim(
  String id,
  String stroke,
  int distance,
  int cs, {
  String course = 'scm',
  String swimmer = 'ana',
  DateTime? date,
}) => SwimResult(
  id: id,
  swimmerId: swimmer,
  course: course,
  stroke: stroke,
  distance: distance,
  timeCs: cs,
  meetName: 'Meet $id',
  date: date ?? DateTime(2026, 11, 1),
);

Swimmer swimmer(String id) => Swimmer(
  id: id,
  firstName: id,
  lastName: 'X',
  birthDate: DateTime(2013, 1, 1),
  gender: 'female',
);

void main() {
  test('times are written the way swimmers write them', () {
    expect(formatSwimTime(2984), '29.84');
    expect(formatSwimTime(6542), '1:05.42');
    expect(formatSwimTime(6005), '1:00.05');
    expect(formatSwimTime(96233), '16:02.33');
    expect(formatTimeDiff(-68), '-0.68');
    expect(formatTimeDiff(120), '+1.20');
  });

  test('typed times are read in hundredths', () {
    expect(parseSwimTime('1:05.42'), 6542);
    expect(parseSwimTime('29.84'), 2984);
    expect(parseSwimTime('29.8'), 2980);
    expect(parseSwimTime('29,84'), 2984);
    expect(parseSwimTime('65.42'), 6542);
    expect(parseSwimTime('1.05.42'), 6542);
    expect(parseSwimTime('1:05'), 6500);
    expect(parseSwimTime(' 16:02.33 '), 96233);
    expect(parseSwimTime(''), isNull);
    expect(parseSwimTime('abc'), isNull);
    expect(parseSwimTime('1:65.00'), isNull);
    expect(parseSwimTime('1:5.00'), isNull);
    expect(parseSwimTime('0'), isNull);
    expect(parseSwimTime('29.845'), isNull);
  });

  test('the event list follows the agreed strokes and distances', () {
    expect(swimEvents('scm').length, 18);
    expect(swimEvents('lcm').length, 17);
    expect(swimEvents('lcm').contains(const SwimEvent('im', 100)), isFalse);
    expect(swimEvents('scm').first.label, '50 Free');
    expect(const SwimEvent('im', 200).label, '200 IM');
  });

  test('a PB is the fastest swim per event, earliest when tied', () {
    final results = [
      swim('a', 'free', 100, 6610),
      swim('b', 'free', 100, 6542, date: DateTime(2026, 11, 8)),
      swim('c', 'free', 100, 6542, date: DateTime(2026, 11, 20)),
      swim('d', 'free', 50, 2984),
      swim('e', 'back', 50, 3520, course: 'lcm'),
    ];
    final scm = personalBests(results, 'scm');
    expect(scm.map((r) => r.id), ['d', 'b']);
    expect(personalBests(results, 'lcm').map((r) => r.id), ['e']);
    expect(
      swimsIn(results, 'scm', const SwimEvent('free', 100)).map((r) => r.id),
      ['b', 'c', 'a'],
    );
  });

  test('a PB is NEW for 30 days', () {
    final today = DateTime(2026, 11, 28);
    expect(
      isNewPb(
        swim('a', 'free', 50, 1, date: DateTime(2026, 10, 29)),
        today: today,
      ),
      isTrue,
    );
    expect(
      isNewPb(
        swim('a', 'free', 50, 1, date: DateTime(2026, 10, 28)),
        today: today,
      ),
      isFalse,
    );
  });

  test('team bests rank each swimmer once, by their best time', () {
    final results = [
      swim('a1', 'free', 100, 6610, swimmer: 'ana'),
      swim('a2', 'free', 100, 6400, swimmer: 'ana'),
      swim('b1', 'free', 100, 6500, swimmer: 'bea'),
      swim('c1', 'free', 100, 6000, swimmer: 'left'),
    ];
    final ranking = teamRanking(results, [swimmer('ana'), swimmer('bea')]);
    expect(ranking.map((t) => '${t.swimmer.id} ${t.best.timeCs}'), [
      'ana 6400',
      'bea 6500',
    ]);
  });
}
