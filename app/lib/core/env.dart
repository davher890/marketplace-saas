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

  /// Page of the deployed website, e.g. `privacidad.html`: this same site on
  /// web, the site behind [apiBaseUrl] elsewhere (the API and the web app are
  /// one Vercel deployment).
  static Uri sitePage(String path) => apiBaseUrl.isEmpty
      ? Uri.base.resolve('/$path')
      : Uri.parse('$apiBaseUrl/$path');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
