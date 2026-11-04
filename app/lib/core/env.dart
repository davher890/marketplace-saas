/// Compile-time configuration, injected with `--dart-define` or
/// `--dart-define-from-file=env.json` (see `env.example.json`).
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Publishable key (`sb_publishable_...`) or the legacy anon key.
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Base URL of the Vercel API (e.g. `https://dona-galleta.vercel.app`).
  /// Leave empty on web to use the same origin the app is served from.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
