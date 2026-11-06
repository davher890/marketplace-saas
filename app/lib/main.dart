import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/auth.dart';
import 'core/env.dart';
import 'core/push_notifications.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/url/url_fragment.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // Clean web URLs (/product/x instead of /#/product/x).
  await initializeDateFormatting('es_ES');

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  // The session: the one an email link brings, or the stored one.
  final store = SecureSessionStore();
  var session = await store.read();
  final link = AuthLink.fromUrl(Uri.base);
  if (link != null) {
    clearUrlFragment();
    if (link.session != null) {
      session = link.session;
      await store.write(session);
    }
  }

  final pushEnabled = await initPushNotifications();
  runApp(
    ProviderScope(
      overrides: [
        pushEnabledProvider.overrideWithValue(pushEnabled),
        sessionStoreProvider.overrideWithValue(store),
        initialSessionProvider.overrideWithValue(session),
        authLinkProvider.overrideWithValue(link),
      ],
      child: const DonaGalletaApp(),
    ),
  );
  if (link != null) _announce(link);
}

/// Tells the user what the email link they opened did.
void _announce(AuthLink link) {
  final message = link.error != null
      ? 'El enlace no es válido o ha caducado. Pide uno nuevo.'
      : link.type == 'signup'
      ? 'Tu cuenta está confirmada. ¡Bienvenida a Doña Galleta!'
      : null;
  if (message == null) return;
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    ),
  );
}

class DonaGalletaApp extends ConsumerWidget {
  const DonaGalletaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminPushProvider);
    return MaterialApp.router(
      title: 'Doña Galleta',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown when the app was built without SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Missing configuration.\n\n'
              'Run with: flutter run --dart-define-from-file=env.json\n'
              '(create env.json with API_BASE_URL, the URL of the API)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
