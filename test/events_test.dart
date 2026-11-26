import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:swimbase/models.dart';
import 'package:swimbase/screens/events_tab.dart';
import 'package:swimbase/widgets/swimmer_events.dart';

final club = Membership(
  clubId: 'c',
  clubName: 'Club',
  clubStatus: 'approved',
  role: 'assistant_coach',
  canCreateGroups: false,
  canMoveSwimmers: false,
);
final groups = [
  Group(id: 'g1', name: 'Gold', level: 3),
  Group(id: 'g2', name: 'Silver', level: 2),
];

/// A tall phone screen, so the whole form is built at once.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('event form checks the title and the groups before saving', (
    tester,
  ) async {
    tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: EventFormScreen(club: club, groups: groups),
      ),
    );
    expect(find.text('New event'), findsOneWidget);
    // Meets have a pool course; socials don't.
    expect(find.text('LCM (50 m)'), findsOneWidget);
    await tester.tap(find.text('Social'));
    await tester.pump();
    expect(find.text('LCM (50 m)'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Give the event a title.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Christmas party');
    await tester.tap(find.text('Whole club'));
    await tester.pump();
    expect(find.text('Gold'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text('Pick at least one group, or Whole club.'),
      findsOneWidget,
    );
  });

  testWidgets('editing an event fills in the form and offers delete', (
    tester,
  ) async {
    final event = ClubEvent(
      id: 'e',
      title: 'Regional Champs',
      kind: 'meet',
      startDate: DateTime(2026, 12, 12),
      endDate: DateTime(2026, 12, 13),
      course: 'lcm',
      wholeClub: false,
      groupIds: ['g1'],
      cancelsTraining: true,
    );
    tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: EventFormScreen(club: club, groups: groups, event: event),
      ),
    );
    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('Regional Champs'), findsOneWidget);
    expect(find.byTooltip('Delete event'), findsOneWidget);
    expect(find.text('Notify families of the change'), findsOneWidget);
  });

  testWidgets('event row shows when, where and tags', (tester) async {
    final event = ClubEvent(
      id: 'e',
      title: 'Regional Champs',
      kind: 'meet',
      startDate: DateTime(2026, 12, 12),
      endDate: DateTime(2026, 12, 12),
      venue: 'City Aquatic Centre',
      course: 'scm',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventTile(event: event, onTap: () {}),
        ),
      ),
    );
    expect(
      find.text('Sat 12 Dec  ·  City Aquatic Centre  ·  SCM'),
      findsOneWidget,
    );
  });
}
