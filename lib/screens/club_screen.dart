import 'package:material_ui/material_ui.dart';

import '../models.dart';
import 'groups_screen.dart';

/// A coach's view of one club. For now it opens straight on Groups; the
/// Today, Calendar, Times and Club tabs are added in later updates.
class ClubScreen extends StatelessWidget {
  const ClubScreen({super.key, required this.club});
  final Membership club;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${club.clubName}: Groups')),
      body: GroupsScreen(club: club),
    );
  }
}
