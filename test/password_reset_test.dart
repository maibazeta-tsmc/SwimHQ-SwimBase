import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:swimbase/password_reset.dart';
import 'package:swimbase/screens/password_screens.dart';

void main() {
  const site = 'https://maibazeta-tsmc.github.io/SwimHQ-SwimBase/';

  test('reset emails link back to the app address, without extras', () {
    expect(appAddress(Uri.parse('$site?code=abc#/')), site);
    expect(
      appAddress(Uri.parse('http://localhost:8080/#/')),
      'http://localhost:8080/',
    );
  });

  test('reads the one-time code from a reset link', () {
    final link = ResetLink.fromUri(
      Uri.parse('$site?token_hash=pkce_123&type=recovery'),
    );
    expect(link.tokenHash, 'pkce_123');
    expect(link.error, isNull);
  });

  test('ignores codes that are not for password resets', () {
    expect(
      ResetLink.fromUri(Uri.parse('$site?token_hash=1&type=signup')).isEmpty,
      isTrue,
    );
    expect(ResetLink.fromUri(Uri.parse(site)).isEmpty, isTrue);
    expect(ResetLink.fromUri(Uri.parse('$site#/')).isEmpty, isTrue);
  });

  test('explains an expired link', () {
    final link = ResetLink.fromUri(
      Uri.parse(
        '$site#error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired',
      ),
    );
    expect(link.error, expiredLinkMessage);
  });

  test('checks the new password', () {
    expect(checkNewPassword('abc', 'abc'), isNotNull);
    expect(checkNewPassword('abcdef', 'abcdeg'), isNotNull);
    expect(checkNewPassword('abcdef', 'abcdef'), isNull);
  });

  testWidgets('forgot password asks for an email before sending', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(
      find.text('Type the email address you sign in with.'),
      findsOneWidget,
    );
  });

  testWidgets('new password screen catches a mismatch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SetNewPasswordScreen(onDone: () {})),
    );
    await tester.enterText(find.byType(TextField).first, 'swim1234');
    await tester.enterText(find.byType(TextField).last, 'swim12345');
    await tester.tap(find.text('Save new password'));
    await tester.pump();
    expect(find.text("The two passwords don't match."), findsOneWidget);
  });
}
