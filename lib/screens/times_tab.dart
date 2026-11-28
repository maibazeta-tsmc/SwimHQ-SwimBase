import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'team_bests_screen.dart';
import 'time_form.dart';

/// The coach's Times tab: add a time for any swimmer, open Team bests,
/// and see (and fix) the times added most recently. Reading Hy-Tek PDFs
/// and Team Records come in later updates.
class TimesTab extends StatefulWidget {
  const TimesTab({super.key, required this.club});
  final Membership club;

  @override
  State<TimesTab> createState() => _TimesTabState();
}

class _TimesData {
  _TimesData(this.swimmers, this.recent);
  final List<Swimmer> swimmers; // active swimmers, by name
  final List<SwimResult> recent; // newest first

  Swimmer? swimmer(String id) {
    for (final s in swimmers) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class _TimesTabState extends State<TimesTab> {
  late Future<_TimesData> _data = _load();

  Future<_TimesData> _load() async {
    final clubId = widget.club.clubId;
    final results = await Future.wait([
      db
          .from('swimmers')
          .select(swimmerColumns)
          .eq('club_id', clubId)
          .eq('status', 'active')
          .order('first_name')
          .order('last_name'),
      db
          .from('swim_results')
          .select(swimResultColumns)
          .eq('club_id', clubId)
          .order('created_at', ascending: false)
          .limit(30),
    ]);
    return _TimesData(
      [for (final r in results[0]) Swimmer.fromRow(r)],
      [for (final r in results[1]) SwimResult.fromRow(r)],
    );
  }

  void _refresh() => setState(() => _data = _load());

  Future<void> _open(_TimesData data, {SwimResult? result}) async {
    final swimmers = result == null
        ? data.swimmers
        : [?data.swimmer(result.swimmerId)];
    if (swimmers.isEmpty) return;
    final changed = await openTimeForm(
      context,
      club: widget.club,
      swimmers: swimmers,
      result: result,
    );
    if (changed && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TimesData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return LoadState(error: snapshot.error, onRetry: _refresh);
        }
        final text = Theme.of(context).textTheme;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: data.swimmers.isEmpty
                          ? null
                          : () => _open(data),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a time'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamBestsScreen(club: widget.club),
                        ),
                      ),
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text('Team bests'),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'To see or fix all of one swimmer\'s times, open them '
                  'from Groups. Reading Hy-Tek results PDFs comes in a '
                  'later update.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Recently added', style: text.titleMedium),
              ),
              if (data.recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('No times added yet.'),
                ),
              for (final r in data.recent)
                ListTile(
                  dense: true,
                  title: Text(
                    '${data.swimmer(r.swimmerId)?.fullName ?? 'Swimmer who left'}'
                    '  ·  ${r.event.label} ${r.course.toUpperCase()}',
                  ),
                  subtitle: Text('${r.meetName}  ·  ${formatDate(r.date)}'),
                  trailing: Text(
                    formatSwimTime(r.timeCs),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  onTap: data.swimmer(r.swimmerId) == null
                      ? null
                      : () => _open(data, result: r),
                ),
            ],
          ),
        );
      },
    );
  }
}
