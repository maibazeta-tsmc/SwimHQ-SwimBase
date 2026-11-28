import 'package:material_ui/material_ui.dart';

import '../models.dart';
import 'club_tab.dart';
import 'events_tab.dart';
import 'groups_screen.dart';
import 'times_tab.dart';
import 'today_tab.dart';

/// A coach's view of one club, with Today, Groups, Events, Times and Club
/// tabs at the bottom.
class ClubScreen extends StatefulWidget {
  const ClubScreen({super.key, required this.club});
  final Membership club;

  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    return Scaffold(
      appBar: AppBar(title: Text(club.clubName)),
      body: IndexedStack(
        index: _tab,
        children: [
          TodayTab(club: club),
          GroupsScreen(club: club),
          EventsTab(club: club),
          TimesTab(club: club),
          ClubTab(
            club: club,
            // After a head coach handover, go back to the home screen so
            // the club opens again with the new permissions.
            onRoleChanged: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Groups'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Events'),
          NavigationDestination(icon: Icon(Icons.timer), label: 'Times'),
          NavigationDestination(icon: Icon(Icons.badge), label: 'Club'),
        ],
      ),
    );
  }
}
