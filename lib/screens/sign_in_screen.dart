import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'password_screens.dart';

/// Email and password sign-in, with a switch to create an account.
/// Google and Apple sign-in come in a later phase.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.initialMessage});

  /// A note to show under the buttons, such as "that reset link expired".
  final String? initialMessage;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  late String? _message = widget.initialMessage;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_creating) {
        final result = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
          // On the website, the confirmation email links back here.
          emailRedirectTo: Uri.base.removeFragment().toString(),
        );
        if (result.session == null) {
          _message =
              'Check your email and tap the link to confirm your '
              'account, then sign in.';
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      _message = e.message;
    } catch (e) {
      _message = 'Something went wrong. Please try again.';
    }
    if (mounted) setState(() => _busy = false);
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
                  const Icon(Icons.pool, size: 56),
                  const SizedBox(height: 8),
                  Text(
                    'SwimBase',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  if (_creating) ...[
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      autofillHints: const [AutofillHints.name],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (!_creating)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ForgotPasswordScreen(
                                    email: _email.text.trim(),
                                  ),
                                ),
                              ),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  SizedBox(height: _creating ? 20 : 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_creating ? 'Create account' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _creating = !_creating;
                            _message = null;
                          }),
                    child: Text(
                      _creating
                          ? 'I already have an account'
                          : 'New here? Create an account',
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 32),
                  // Shows which Supabase project this build talks to, to
                  // help spot a wrong address. The address is not secret.
                  Text(
                    'Server: ${Uri.tryParse(AppConfig.supabaseUrl)?.host ?? AppConfig.supabaseUrl}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
