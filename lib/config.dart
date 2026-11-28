/// Settings that connect the app to your Supabase project.
///
/// These are NOT typed into the code. They are passed in when the app is
/// built, from the file `env.json` on your computer (which is never uploaded
/// to GitHub) or from GitHub's "Secrets" when the website is built online.
/// See the README for step-by-step instructions.
class AppConfig {
  static const _rawUrl = String.fromEnvironment('SUPABASE_URL');
  static const _rawKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// The project address, cleaned up (see [cleanSupabaseUrl]).
  static final supabaseUrl = cleanSupabaseUrl(_rawUrl);

  /// The publishable key, with stray spaces, line breaks and quotes removed.
  static final supabasePublishableKey = cleanValue(_rawKey);

  /// True once both settings have been provided.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}

/// Removes spaces, line breaks and wrapping quotes that easily sneak in
/// when a value is copied and pasted.
String cleanValue(String value) {
  var v = value.trim();
  while (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    v = v.substring(1, v.length - 1).trim();
  }
  return v;
}

/// Turns whatever was pasted into the plain project address the Supabase
/// library expects, like `https://abcd1234.supabase.co`.
///
/// Handles the common copy-and-paste slips:
/// - extra paths such as `/rest/v1/` or `/auth/v1`, and trailing slashes
/// - a missing `https://`
/// - the dashboard address (`supabase.com/dashboard/project/<id>`)
String cleanSupabaseUrl(String value) {
  var v = cleanValue(value);
  if (v.isEmpty) return v;

  final dashboard =
      RegExp(r'supabase\.com/dashboard/project/([a-z0-9]+)').firstMatch(v);
  if (dashboard != null) {
    return 'https://${dashboard.group(1)}.supabase.co';
  }

  if (!v.contains('://')) v = 'https://$v';
  final uri = Uri.tryParse(v);
  if (uri == null || uri.host.isEmpty) return v;

  // Hosted Supabase projects live at the root of their address, so any
  // path after it (like /rest/v1/) is a paste slip and must be dropped.
  if (uri.host.endsWith('.supabase.co')) {
    return '${uri.scheme}://${uri.host}';
  }

  // Self-hosted or local addresses: keep the path, minus known API suffixes.
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  path = path.replaceAll(RegExp(r'/(rest|auth|storage|realtime|functions)/v1$'), '');
  return '${uri.scheme}://${uri.authority}$path';
}
