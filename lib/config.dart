/// Settings that connect the app to your Supabase project.
///
/// These are NOT typed into the code. They are passed in when the app is
/// built, from the file `env.json` on your computer (which is never uploaded
/// to GitHub) or from GitHub's "Secrets" when the website is built online.
/// See the README for step-by-step instructions.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// True once both settings have been provided.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
