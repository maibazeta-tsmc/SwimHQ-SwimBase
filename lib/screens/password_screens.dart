import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../password_reset.dart';

/// Asks for an email address and sends a "reset your password" email.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  /// Whatever was already typed on the sign-in screen.
  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  bool _sent = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _message = 'Type the email address you sign in with.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        // The link in the email opens the app again, here.
        redirectTo: appAddress(Uri.base),
      );
      _sent = true;
    } on AuthException catch (e) {
      _message = e.statusCode == '429'
          ? 'Too many emails were sent in the last hour. '
                'Please wait a while and try again.'
          : e.message;
    } catch (_) {
      _message = 'Something went wrong. Please try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sent
                  ? [
                      const Icon(Icons.mark_email_read_outlined, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'If ${_email.text.trim()} has a SwimBase account, '
                        "we've sent it a link to set a new password.\n\n"
                        'It can take a few minutes. Check your spam folder '
                        'too. The link works once.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to sign in'),
                      ),
                    ]
                  : [
                      const Text(
                        "Type your email and we'll send you a link to "
                        'set a new password.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        onSubmitted: (_) => _busy ? null : _send(),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _send,
                        child: const Text('Send reset link'),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(_message!, textAlign: TextAlign.center),
                      ],
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown after someone opens the link from a reset email. They are signed
/// in by the link and pick a new password here.
class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key, required this.onDone});

  /// Called once the password is saved, or when they cancel.
  final VoidCallback onDone;

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = checkNewPassword(_password.text, _repeat.text);
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Password changed. You are signed in.')),
      );
      widget.onDone();
      return;
    } on AuthException catch (e) {
      _message = e.message;
    } catch (_) {
      _message = 'Something went wrong. Please try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cancel() async {
    await Supabase.instance.client.auth.signOut();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_reset, size: 56),
                  const SizedBox(height: 8),
                  Text(
                    'Set a new password',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _repeat,
                    decoration: const InputDecoration(
                      labelText: 'Type the new password again',
                    ),
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _busy ? null : _save(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Save new password'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: const Text('Cancel'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
