import 'package:flutter/foundation.dart';

/// Compile-time configuration, injected with `--dart-define` or
/// `--dart-define-from-file=env.json` (see README "Run the app").
class Env {
  const Env._();

  /// Base URL of the Vercel API (e.g. `https://dona-galleta.vercel.app`).
  /// Leave empty on web to use the same origin the app is served from.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Page of the deployed website, e.g. `privacidad.html`: this same site on
  /// web, the site behind [apiBaseUrl] elsewhere (the API and the web app are
  /// one Vercel deployment).
  static Uri sitePage(String path) => apiBaseUrl.isEmpty
      ? Uri.base.resolve('/$path')
      : Uri.parse('$apiBaseUrl/$path');

  /// The app only talks to the API. On the web it can be on the same origin;
  /// elsewhere its URL is needed.
  static bool get isConfigured => kIsWeb || apiBaseUrl.isNotEmpty;
}
