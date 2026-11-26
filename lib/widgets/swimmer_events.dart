import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic.dart';
import '../models.dart';
import 'common.dart';

/// One event as a list row: icon, title, when and where, with small tags.
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    required this.onTap,
    this.extra,
  });
  final ClubEvent event;
  final VoidCallback onTap;

  /// An extra line under the event, e.g. the groups it is for.
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final scheme = Theme.of(context).colorScheme;
    // One short line: when, where, course, and "Updated" after a change.
    final line = [
      eventWhen(e),
      if (e.venue != null) e.venue!,
      if (e.course != null) e.course!.toUpperCase(),
      if (recentlyUpdated(e)) 'Updated',
    ].join('  ·  ');
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: Icon(switch (e.kind) {
        'meet' => Icons.emoji_events,
        'social' => Icons.celebration,
        _ => Icons.event,
      }, color: scheme.primary),
      title: Text(e.title),
      subtitle: Text(extra == null ? line : '$line\n$extra'),
      isThreeLine: extra != null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Opens a web page or map in the browser.
Future<void> _open(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not open it.')));
  }
}

/// The full event: date, time, place with a map link, course, notes and
/// the web link.
Future<void> showEventDetails(BuildContext context, ClubEvent e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  eventKindLabel(e.kind),
                  if (recentlyUpdated(e)) 'Updated recently',
                ].join('  ·  '),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(eventWhen(e)),
                subtitle: e.allDay ? const Text('All day') : null,
              ),
              if (e.venue != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place),
                  title: Text(e.venue!),
                  subtitle: const Text('Open in Maps'),
                  onTap: () => _open(context, mapsLink(e.venue!)),
                ),
              if (e.course != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pool),
                  title: Text(courseLabel(e.course!)),
                ),
              if (e.notes != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notes),
                  title: Text(e.notes!),
                ),
              if (e.link != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(e.link!),
                  subtitle: const Text('More information'),
                  onTap: () => _open(context, Uri.parse(e.link!)),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// One swimmer's upcoming events (the next 6 months): whole-club events
/// and events for the swimmer's group. With [limit], shows only the first
/// few and a "See all" button.
class SwimmerEvents extends StatefulWidget {
  const SwimmerEvents({super.key, required this.swimmerId, this.limit});
  final String swimmerId;
  final int? limit;

  @override
  State<SwimmerEvents> createState() => _SwimmerEventsState();
}

class _SwimmerEventsState extends State<SwimmerEvents> {
  late Future<List<ClubEvent>> _events = _load();

  Future<List<ClubEvent>> _load() async {
    final from = dateOnly();
    final rows = await db.rpc(
      'swimmer_events',
      params: {
        'p_swimmer_id': widget.swimmerId,
        'p_from': dbDate(from),
        'p_to': dbDate(from.add(const Duration(days: 183))),
      },
    );
    return [for (final r in rows as List) ClubEvent.fromRow(r)];
  }

  @override
  void didUpdateWidget(SwimmerEvents old) {
    super.didUpdateWidget(old);
    if (old.swimmerId != widget.swimmerId) _events = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClubEvent>>(
      future: _events,
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null) {
          return LoadState(
            error: snapshot.error,
            onRetry: () => setState(() => _events = _load()),
          );
        }
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No upcoming events yet.'),
          );
        }
        final limit = widget.limit;
        final shown = limit == null ? events : events.take(limit);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in shown)
              EventTile(event: e, onTap: () => showEventDetails(context, e)),
            if (limit != null && events.length > limit)
              SeeAllButton(
                count: events.length,
                title: 'Upcoming events',
                page: SwimmerEvents(swimmerId: widget.swimmerId),
              ),
          ],
        );
      },
    );
  }
}
