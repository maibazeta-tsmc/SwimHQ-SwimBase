import 'package:material_ui/material_ui.dart';

import '../logic.dart';
import '../models.dart';
import '../screens/time_form.dart';
import 'common.dart';

/// One swimmer's personal bests, with an LCM / SCM toggle: one line per
/// event with the best Time, Meet and Date, and a NEW tag for PBs from
/// the last 30 days. Tap an event to see every swim in it.
/// Coaches (when [club] is a coach membership) also get "Add a time",
/// and can tap a swim to fix or delete it.
class SwimmerBests extends StatefulWidget {
  const SwimmerBests({super.key, required this.swimmer, required this.club});
  final Swimmer swimmer;
  final Membership club;

  @override
  State<SwimmerBests> createState() => _SwimmerBestsState();
}

class _SwimmerBestsState extends State<SwimmerBests> {
  late Future<List<SwimResult>> _results = _load();
  String _course = 'lcm';
  bool _courseChosen = false;

  bool get _isCoach => widget.club.isCoach;

  Future<List<SwimResult>> _load() async {
    final rows = await db
        .from('swim_results')
        .select(swimResultColumns)
        .eq('swimmer_id', widget.swimmer.id);
    final list = [for (final r in rows) SwimResult.fromRow(r)];
    // Open on the course with times, if only one has any.
    if (!_courseChosen &&
        list.isNotEmpty &&
        !list.any((r) => r.course == _course)) {
      _course = list.first.course;
    }
    return list;
  }

  void _refresh() => setState(() => _results = _load());

  @override
  void didUpdateWidget(SwimmerBests old) {
    super.didUpdateWidget(old);
    if (old.swimmer.id != widget.swimmer.id) {
      _courseChosen = false;
      _course = 'lcm';
      _results = _load();
    }
  }

  Future<void> _add() async {
    final changed = await openTimeForm(
      context,
      club: widget.club,
      swimmers: [widget.swimmer],
      course: _course,
    );
    if (changed && mounted) _refresh();
  }

  Future<void> _openEvent(List<SwimResult> all, SwimEvent event) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EventSwimsScreen(
          club: widget.club,
          swimmer: widget.swimmer,
          course: _course,
          event: event,
          swims: swimsIn(all, _course, event),
        ),
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SwimResult>>(
      future: _results,
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return LoadState(error: snapshot.error, onRetry: _refresh);
        }
        final bests = personalBests(all, _course);
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(horizontal: -2, vertical: -3),
                ),
                segments: [
                  for (final c in courses)
                    ButtonSegment(value: c, label: Text(courseShort(c))),
                ],
                selected: {_course},
                onSelectionChanged: (s) => setState(() {
                  _course = s.first;
                  _courseChosen = true;
                }),
              ),
            ),
            if (bests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _isCoach
                      ? 'No ${_course.toUpperCase()} times yet. '
                            'Tap Add a time to enter one.'
                      : 'No ${_course.toUpperCase()} times yet. Your '
                            'coach adds times after meets and time trials.',
                ),
              ),
            for (final b in bests)
              ListTile(
                dense: true,
                title: Row(
                  children: [
                    Expanded(child: Text(b.event.label)),
                    if (isNewPb(b))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ),
                    Text(
                      formatSwimTime(b.timeCs),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                subtitle: Text('${b.meetName}  ·  ${formatDate(b.date)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openEvent(all, b.event),
              ),
            if (bests.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('NEW = best time set in the last 30 days.'),
              ),
            if (_isCoach)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.tonalIcon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a time'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Every swim one swimmer has in one event and course, fastest first.
/// Coaches can tap a swim to change or delete it.
class _EventSwimsScreen extends StatefulWidget {
  const _EventSwimsScreen({
    required this.club,
    required this.swimmer,
    required this.course,
    required this.event,
    required this.swims,
  });
  final Membership club;
  final Swimmer swimmer;
  final String course;
  final SwimEvent event;
  final List<SwimResult> swims;

  @override
  State<_EventSwimsScreen> createState() => _EventSwimsScreenState();
}

class _EventSwimsScreenState extends State<_EventSwimsScreen> {
  late List<SwimResult> _swims = widget.swims;
  bool _changed = false;

  Future<void> _reload() async {
    final rows = await db
        .from('swim_results')
        .select(swimResultColumns)
        .eq('swimmer_id', widget.swimmer.id)
        .eq('course', widget.course)
        .eq('stroke', widget.event.stroke)
        .eq('distance', widget.event.distance);
    if (!mounted) return;
    setState(() {
      _changed = true;
      _swims = swimsIn(
        [for (final r in rows) SwimResult.fromRow(r)],
        widget.course,
        widget.event,
      );
    });
  }

  Future<void> _open({SwimResult? result}) async {
    final changed = await openTimeForm(
      context,
      club: widget.club,
      swimmers: [widget.swimmer],
      result: result,
      course: widget.course,
      event: widget.event,
    );
    if (changed) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isCoach = widget.club.isCoach;
    final title =
        '${widget.event.label} ${widget.course.toUpperCase()}  ·  '
        '${widget.swimmer.firstName}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        floatingActionButton: isCoach
            ? FloatingActionButton.extended(
                onPressed: () => _open(),
                icon: const Icon(Icons.add),
                label: const Text('Add a time'),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            if (_swims.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No times in this event any more.'),
              ),
            for (final (i, r) in _swims.indexed)
              ListTile(
                leading: i == 0
                    ? const Icon(Icons.emoji_events_outlined)
                    : const SizedBox(width: 24),
                title: Text(
                  formatSwimTime(r.timeCs) +
                      (i == 0
                          ? '  (PB)'
                          : '  ${formatTimeDiff(r.timeCs - _swims.first.timeCs)}'),
                ),
                subtitle: Text('${r.meetName}  ·  ${formatDate(r.date)}'),
                trailing: isCoach ? const Icon(Icons.edit_outlined) : null,
                onTap: isCoach ? () => _open(result: r) : null,
              ),
          ],
        ),
      ),
    );
  }
}
