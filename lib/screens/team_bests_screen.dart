import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Team bests: the club's swimmers ranked by their best time in one
/// event, filtered by group, gender and age. Shows name and time only.
/// For coaches and swimmers; parents don't get this view.
class TeamBestsScreen extends StatefulWidget {
  const TeamBestsScreen({super.key, required this.club});
  final Membership club;

  @override
  State<TeamBestsScreen> createState() => _TeamBestsScreenState();
}

class _TeamData {
  _TeamData(this.swimmers, this.groups);
  final List<Swimmer> swimmers; // active swimmers
  final List<Group> groups;
}

class _TeamBestsScreenState extends State<TeamBestsScreen> {
  late final Future<_TeamData> _team = _loadTeam();
  late Future<List<SwimResult>> _results = _loadResults();
  String _course = 'lcm';
  SwimEvent _event = const SwimEvent('free', 100);
  String? _groupId; // null = all groups
  String? _gender; // null = everyone
  int? _ageGroup; // index into ageGroups; null = all ages

  Future<_TeamData> _loadTeam() async {
    final results = await Future.wait([
      db
          .from('swimmers')
          .select(swimmerColumns)
          .eq('club_id', widget.club.clubId)
          .eq('status', 'active'),
      db
          .from('groups')
          .select()
          .eq('club_id', widget.club.clubId)
          .isFilter('archived_at', null),
    ]);
    return _TeamData([
      for (final r in results[0]) Swimmer.fromRow(r),
    ], sortGroups([for (final r in results[1]) Group.fromRow(r)]));
  }

  Future<List<SwimResult>> _loadResults() async {
    final rows = await db
        .from('swim_results')
        .select(swimResultColumns)
        .eq('club_id', widget.club.clubId)
        .eq('course', _course)
        .eq('stroke', _event.stroke)
        .eq('distance', _event.distance);
    return [for (final r in rows) SwimResult.fromRow(r)];
  }

  void _reload() => setState(() => _results = _loadResults());

  bool _keep(Swimmer s) {
    if (_groupId != null && s.currentGroupId != _groupId) return false;
    if (_gender != null && s.gender != _gender) return false;
    if (_ageGroup != null) {
      final (_, from, to) = ageGroups[_ageGroup!];
      final age = ageOn(s.birthDate);
      if (age < from || (to != null && age > to)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    const compact = VisualDensity(horizontal: -2, vertical: -3);
    return Scaffold(
      appBar: AppBar(title: const Text('Team bests')),
      body: FutureBuilder<_TeamData>(
        future: _team,
        builder: (context, teamSnap) {
          final team = teamSnap.data;
          if (team == null) {
            return LoadState(error: teamSnap.error);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<String>(
                  style: const ButtonStyle(visualDensity: compact),
                  showSelectedIcon: false,
                  segments: [
                    for (final c in courses)
                      ButtonSegment(value: c, label: Text(courseShort(c))),
                  ],
                  selected: {_course},
                  onSelectionChanged: (s) {
                    _course = s.first;
                    if (!swimEvents(_course).contains(_event)) {
                      _event = const SwimEvent('free', 100);
                    }
                    _reload();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    DropdownMenu<SwimEvent>(
                      key: ValueKey('event-$_course'),
                      width: 150,
                      label: const Text('Event'),
                      initialSelection: _event,
                      dropdownMenuEntries: [
                        for (final e in swimEvents(_course))
                          DropdownMenuEntry(value: e, label: e.label),
                      ],
                      onSelected: (e) {
                        if (e == null) return;
                        _event = e;
                        _reload();
                      },
                    ),
                    DropdownMenu<String?>(
                      width: 150,
                      label: const Text('Group'),
                      initialSelection: _groupId,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry(
                          value: null,
                          label: 'All groups',
                        ),
                        for (final g in team.groups)
                          DropdownMenuEntry(value: g.id, label: g.name),
                      ],
                      onSelected: (v) => setState(() => _groupId = v),
                    ),
                    DropdownMenu<String?>(
                      width: 150,
                      label: const Text('Gender'),
                      initialSelection: _gender,
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: null, label: 'Everyone'),
                        DropdownMenuEntry(value: 'female', label: 'Female'),
                        DropdownMenuEntry(value: 'male', label: 'Male'),
                      ],
                      onSelected: (v) => setState(() => _gender = v),
                    ),
                    DropdownMenu<int?>(
                      width: 150,
                      label: const Text('Age'),
                      initialSelection: _ageGroup,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry(value: null, label: 'All ages'),
                        for (final (i, a) in ageGroups.indexed)
                          DropdownMenuEntry(value: i, label: a.$1),
                      ],
                      onSelected: (v) => setState(() => _ageGroup = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<SwimResult>>(
                future: _results,
                builder: (context, snapshot) {
                  final results = snapshot.data;
                  if (results == null) {
                    return LoadState(error: snapshot.error, onRetry: _reload);
                  }
                  final ranking = teamRanking(
                    results,
                    team.swimmers.where(_keep),
                  );
                  if (ranking.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No ${_event.label} ${_course.toUpperCase()} times '
                        'for these swimmers yet.',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final (i, t) in ranking.indexed)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text('${i + 1}'),
                          ),
                          title: Text(t.swimmer.fullName),
                          trailing: Text(
                            formatSwimTime(t.best.timeCs),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
