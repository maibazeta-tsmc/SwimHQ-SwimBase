import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase connection, shared by every screen.
SupabaseClient get db => Supabase.instance.client;

/// Runs a database action and shows the outcome at the bottom of the
/// screen: [done] when it worked, the database's own message when not
/// (for example "You don't have permission to move swimmers.").
/// Returns true when it worked.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
  SnackBarAction? undo,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (done != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(done),
          action: undo,
          duration: Duration(seconds: undo == null ? 4 : 10),
        ),
      );
    }
    return true;
  } on PostgrestException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Something went wrong. Check your connection and '
          'try again.',
        ),
      ),
    );
  }
  return false;
}

/// Asks a yes/no question. Returns true if the person tapped [yes].
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'OK',
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return answer == true;
}

/// The colours a coach can pick for a group, saved by name.
const groupColours = <String, Color>{
  'blue': Color(0xFF1E88E5),
  'green': Color(0xFF43A047),
  'yellow': Color(0xFFFDD835),
  'orange': Color(0xFFFB8C00),
  'red': Color(0xFFE53935),
  'purple': Color(0xFF8E24AA),
  'grey': Color(0xFF757575),
  'gold': Color(0xFFC9A227),
  'silver': Color(0xFF9E9E9E),
  'bronze': Color(0xFFA0522D),
};

/// A round badge with the group's level number in the group's colour.
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level, this.colour});

  final int? level;
  final String? colour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = groupColours[colour] ?? scheme.primaryContainer;
    final fg = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return CircleAvatar(
      backgroundColor: level == null ? scheme.surfaceContainerHighest : bg,
      foregroundColor: level == null ? scheme.onSurfaceVariant : fg,
      child: Text(level?.toString() ?? '–'),
    );
  }
}

/// A message shown in place of a list while it loads or when it failed.
class LoadState extends StatelessWidget {
  const LoadState({super.key, this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            error is PostgrestException
                ? (error as PostgrestException).message
                : 'Could not load this. Check your connection.',
          ),
          const SizedBox(height: 8),
          if (onRetry != null)
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
