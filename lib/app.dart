import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'password_reset.dart';
import 'screens/home_screen.dart';
import 'screens/password_screens.dart';
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
///
/// Also handles links from "reset your password" emails: it signs the
/// person in with the link and shows [SetNewPasswordScreen] first.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _sub;

  /// True while someone who opened a reset link still has to pick a
  /// new password.
  bool _settingPassword = false;

  /// True while a reset link is being checked.
  bool _checkingLink = false;

  /// A message for the sign-in screen, such as "that link expired".
  String? _linkMessage;

  @override
  void initState() {
    super.initState();
    _sub = _auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _settingPassword = true;
          } else if (state.event == AuthChangeEvent.signedOut) {
            _settingPassword = false;
          }
        });
      },
      onError: (Object e) {
        // For example a reset link opened in a different browser.
        if (mounted) setState(() => _linkMessage = expiredLinkMessage);
      },
    );
    _openResetLink(ResetLink.fromUri(Uri.base));
  }

  Future<void> _openResetLink(ResetLink link) async {
    if (link.error != null) {
      _linkMessage = link.error;
      return;
    }
    final tokenHash = link.tokenHash;
    if (tokenHash == null) return;
    setState(() => _checkingLink = true);
    try {
      await _auth.verifyOTP(type: OtpType.recovery, tokenHash: tokenHash);
      _settingPassword = true;
    } on AuthException catch (_) {
      // Already used (for example the page was refreshed) or expired.
      if (_auth.currentSession == null) _linkMessage = expiredLinkMessage;
    } catch (_) {
      _linkMessage = 'Something went wrong. Please try again.';
    }
    if (mounted) setState(() => _checkingLink = false);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLink) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_auth.currentSession == null) {
      return SignInScreen(
        key: ValueKey(_linkMessage),
        initialMessage: _linkMessage,
      );
    }
    if (_settingPassword) {
      return SetNewPasswordScreen(
        onDone: () => setState(() => _settingPassword = false),
      );
    }
    return const HomeScreen();
  }
}
