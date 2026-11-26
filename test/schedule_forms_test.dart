import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:swimbase/models.dart';
import 'package:swimbase/screens/schedule_forms.dart';

/// Opens a form from a button so it can be tapped through like a coach would.
Future<void> open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) show,
  void Function(Object?) result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result(await show(context)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('weekly form needs a day, then returns the ticked days', (
    tester,
  ) async {
    Object? got;
    await open(tester, showWeeklyForm, (r) => got = r);
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Tick at least one day.'), findsOneWidget);
    await tester.tap(find.text('Tue'));
    await tester.tap(find.text('Thu'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final form = got as WeeklyForm;
    expect(form.weekdays, {2, 4});
    expect(form.start, 16 * 60 + 30);
    expect(form.end, 19 * 60);
  });

  testWidgets('one-off form can be for several groups', (tester) async {
    Object? got;
    final groups = [
      Group(id: 'g', name: 'Gold', level: 3),
      Group(id: 's', name: 'Silver', level: 2),
    ];
    await open(
      tester,
      (c) => showOneOffForm(c, groupId: 'g', groups: groups),
      (r) => got = r,
    );
    await tester.tap(find.text('Silver'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect((got as OneOffForm).groupIds.toSet(), {'g', 's'});
  });

  testWidgets('rest form offers whole club to the head coach', (tester) async {
    Object? got;
    await open(
      tester,
      (c) => showRestForm(c, groupName: 'Gold', canDoWholeClub: true),
      (r) => got = r,
    );
    await tester.tap(find.text('Break'));
    await tester.tap(find.text('Whole club'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final form = got as RestForm;
    expect(form.isBreak, isTrue);
    expect(form.wholeClub, isTrue);
  });
}
