import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/setup_needed_screen.dart';
import 'screens/sign_in_screen.dart';

/// The whole app. Change the name or colour here.
class SwimBaseApp extends StatelessWidget {
  const SwimBaseApp({super.key, this.configured});

  /// Only used by tests. Normally this comes from [AppConfig].
  final bool? configured;

  static const appName = 'SwimBase';

  @override
  Widget build(BuildContext context) {
    final isConfigured = configured ?? AppConfig.isConfigured;
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0077B6)),
        useMaterial3: true,
      ),
      home: isConfigured ? const AuthGate() : const SetupNeededScreen(),
    );
  }
}

/// Shows the sign-in screen or the home screen, depending on whether
/// someone is signed in. Switches automatically when that changes.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        return session == null ? const SignInScreen() : const HomeScreen();
      },
    );
  }
}
