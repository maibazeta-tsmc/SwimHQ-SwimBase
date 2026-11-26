import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../widgets/common.dart';
import '../widgets/swimmer_attendance.dart';
import '../widgets/swimmer_events.dart';
import '../widgets/swimmer_schedule.dart';

/// What a swimmer or parent sees when they open their club: upcoming
/// events, the training schedule and attendance. PBs come later.
/// A parent with several children picks a child at the top.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.club});
  final Membership club;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late Future<List<Swimmer>> _swimmers = _load();
  String? _chosenId;
  int _version = 0;

  /// The swimmer's own record, or a parent's linked children.
  Future<List<Swimmer>> _load() async {
    final me = db.auth.currentUser!.id;
    final clubId = widget.club.clubId;
    List<dynamic> rows;
    if (widget.club.role == 'swimmer') {
      rows = await db
          .from('swimmers')
          .select(swimmerColumns)
          .eq('club_id', clubId)
          .eq('user_id', me);
    } else {
      final links = await db
          .from('parent_links')
          .select('swimmer_id')
          .eq('club_id', clubId)
          .eq('parent_user_id', me);
      final ids = [for (final l in links) l['swimmer_id'] as String];
      rows = ids.isEmpty
          ? []
          : await db
                .from('swimmers')
                .select(swimmerColumns)
                .inFilter('id', ids)
                .order('first_name');
    }
    return [for (final r in rows) Swimmer.fromRow(r)];
  }

  void _refresh() => setState(() {
    _swimmers = _load();
    _version++;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.club.clubName)),
      body: FutureBuilder<List<Swimmer>>(
        future: _swimmers,
        builder: (context, snapshot) {
          final swimmers = snapshot.data;
          if (swimmers == null) {
            return LoadState(error: snapshot.error, onRetry: _refresh);
          }
          if (swimmers.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No swimmer is linked to your account yet.'),
            );
          }
          final chosen = swimmers.firstWhere(
            (s) => s.id == _chosenId,
            orElse: () => swimmers.first,
          );
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (swimmers.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final s in swimmers)
                          ChoiceChip(
                            label: Text(s.firstName),
                            selected: s.id == chosen.id,
                            onSelected: (_) => setState(() => _chosenId = s.id),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Upcoming events',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SwimmerEvents(
                  key: ValueKey('events-${chosen.id}-$_version'),
                  swimmerId: chosen.id,
                  limit: 3,
                ),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '${chosen.firstName}\'s next training',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SwimmerSchedule(
                  key: ValueKey('${chosen.id}-$_version'),
                  swimmerId: chosen.id,
                  limit: 4,
                  title: '${chosen.firstName}\'s training, next 2 weeks',
                ),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '${chosen.firstName}\'s attendance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SwimmerAttendance(
                  key: ValueKey('attendance-${chosen.id}-$_version'),
                  swimmerId: chosen.id,
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Personal bests are coming in a later update.'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
