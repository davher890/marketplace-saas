import 'package:web/web.dart' as web;

/// Drops `#access_token=...` from the address bar and history, so the tokens
/// aren't left in the URL (bookmarks, screenshots, the back button).
void clearUrlFragment() {
  final location = web.window.location;
  web.window.history.replaceState(
    null,
    '',
    '${location.pathname}${location.search}',
  );
}
