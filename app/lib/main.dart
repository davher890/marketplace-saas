import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/push_notifications.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // Clean web URLs (/product/x instead of /#/product/x).
  await initializeDateFormatting('es_ES');

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );
  final pushEnabled = await initPushNotifications();
  runApp(
    ProviderScope(
      overrides: [pushEnabledProvider.overrideWithValue(pushEnabled)],
      child: const DonaGalletaApp(),
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
              '(create env.json with SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and API_BASE_URL)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
