import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:swimbase/models.dart';
import 'package:swimbase/screens/time_form.dart';

final club = Membership(
  clubId: 'c',
  clubName: 'Club',
  clubStatus: 'approved',
  role: 'assistant_coach',
  canCreateGroups: false,
  canMoveSwimmers: false,
);
final ana = Swimmer(
  id: 's1',
  firstName: 'Ana',
  lastName: 'Reyes',
  birthDate: DateTime(2013, 5, 1),
  gender: 'female',
);

void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('time form checks the event, time and meet before saving', (
    tester,
  ) async {
    tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: TimeFormScreen(club: club, swimmers: [ana]),
      ),
    );
    await tester.pump();
    expect(find.text('Add a time'), findsOneWidget);
    expect(find.text('Ana Reyes'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Pick the event.'), findsOneWidget);
  });

  testWidgets('a time that can\'t be read shows a hint', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: TimeFormScreen(
          club: club,
          swimmers: [ana],
          event: const SwimEvent('free', 100),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Time'), '1:75');
    await tester.pump();
    expect(
      find.text('Type minutes:seconds.hundredths, like 1:05.42'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Type the time like 1:05.42 or 29.84.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Time'), '1:05.42');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Type the meet name.'), findsOneWidget);
  });

  testWidgets('editing a time offers delete', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: TimeFormScreen(
          club: club,
          swimmers: [ana],
          result: SwimResult(
            id: 'r',
            swimmerId: 's1',
            course: 'scm',
            stroke: 'free',
            distance: 100,
            timeCs: 6542,
            meetName: 'Regional Champs',
            date: DateTime(2026, 11, 8),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Edit time'), findsOneWidget);
    expect(find.byTooltip('Delete time'), findsOneWidget);
    expect(find.text('1:05.42'), findsOneWidget);
    expect(find.text('Regional Champs'), findsOneWidget);
  });
}
