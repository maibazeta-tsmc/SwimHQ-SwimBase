/// Helpers for "Forgot password?". Kept free of Supabase calls so they can
/// be tested on their own.
library;

/// The address of the app itself (for example
/// `https://maibazeta-tsmc.github.io/SwimHQ-SwimBase/`), without anything
/// after a `?` or `#`. Reset emails link back here.
String appAddress(Uri current) => Uri(
  scheme: current.scheme,
  host: current.host,
  port: current.hasPort ? current.port : null,
  path: current.path,
).toString();

/// What a reset link put in the address bar when the app opened.
class ResetLink {
  const ResetLink({this.tokenHash, this.error});

  /// The one-time code from the reset email, when the email template
  /// sends `?token_hash=...&type=recovery`.
  final String? tokenHash;

  /// A problem Supabase reported, such as an expired link.
  final String? error;

  bool get isEmpty => tokenHash == null && error == null;

  /// Reads the address the app was opened with. Supabase may put details
  /// after `?` or after `#`, so both are checked.
  static ResetLink fromUri(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    final fragment = uri.fragment.startsWith('/')
        ? uri.fragment.substring(1)
        : uri.fragment;
    if (fragment.contains('=')) {
      try {
        params.addAll(Uri.splitQueryString(fragment));
      } catch (_) {
        // Not a list of settings; ignore it.
      }
    }

    final hash = params['token_hash'];
    if (hash != null && hash.isNotEmpty && params['type'] == 'recovery') {
      return ResetLink(tokenHash: hash);
    }

    final code = params['error_code'];
    final description = params['error_description'];
    if (code == 'otp_expired') {
      return const ResetLink(error: expiredLinkMessage);
    }
    if (description != null && description.isNotEmpty) {
      return ResetLink(error: description);
    }
    return const ResetLink();
  }
}

const expiredLinkMessage =
    'That reset link has expired or was already used. '
    'Tap "Forgot password?" to get a new one.';

/// Checks a new password. Returns a message to show, or null when it's fine.
String? checkNewPassword(String password, String repeat) {
  if (password.length < 6) {
    return 'Use at least 6 characters.';
  }
  if (password != repeat) {
    return "The two passwords don't match.";
  }
  return null;
}
