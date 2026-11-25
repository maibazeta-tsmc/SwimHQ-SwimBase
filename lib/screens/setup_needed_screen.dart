import 'package:material_ui/material_ui.dart';

/// Shown when the app was built without the Supabase settings.
class SetupNeededScreen extends StatelessWidget {
  const SetupNeededScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pool, size: 64),
                const SizedBox(height: 16),
                Text('Almost there',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'The app is running, but it is not connected to the database '
                  'yet. Follow "Connect the app to Supabase" in the README.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
