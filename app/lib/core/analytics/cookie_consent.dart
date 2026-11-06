import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../env.dart';
import '../theme.dart';
import 'analytics_bridge.dart';

/// Talks to the page's Tag Manager loader. Replaced in tests.
class AnalyticsConsentStore {
  const AnalyticsConsentStore();

  bool get available => analyticsAvailable;
  String? get stored => storedAnalyticsConsent;
  void save({required bool granted}) => setAnalyticsConsent(granted: granted);
}

final analyticsConsentStoreProvider = Provider(
  (ref) => const AnalyticsConsentStore(),
);

enum CookieConsent { undecided, granted, denied }

/// The visitor's choice about analytics cookies. Only on the web, and only
/// when Tag Manager is configured (`GTM_ID`); elsewhere it's always denied
/// and no banner is shown.
final cookieConsentProvider =
    NotifierProvider<CookieConsentNotifier, CookieConsent>(
      CookieConsentNotifier.new,
    );

/// Whether to show the banner (no choice yet, or reopened from the footer).
final cookieBannerVisibleProvider = Provider<bool>(
  (ref) => ref.watch(cookieConsentProvider) == CookieConsent.undecided,
);

class CookieConsentNotifier extends Notifier<CookieConsent> {
  AnalyticsConsentStore get _store => ref.read(analyticsConsentStoreProvider);

  @override
  CookieConsent build() {
    if (!_store.available) return CookieConsent.denied;
    return switch (_store.stored) {
      'granted' => CookieConsent.granted,
      'denied' => CookieConsent.denied,
      _ => CookieConsent.undecided,
    };
  }

  /// Whether the site has analytics at all (to show the "Cookies" link).
  bool get available => _store.available;

  void accept() {
    _store.save(granted: true);
    state = CookieConsent.granted;
  }

  void reject() {
    _store.save(granted: false);
    state = CookieConsent.denied;
  }

  /// Shows the banner again so the visitor can change their mind. The
  /// previous choice stays in force until they pick again.
  void reopen() {
    if (_store.available) state = CookieConsent.undecided;
  }
}

/// Bottom banner asking for analytics cookies. Accepting and rejecting are
/// equally easy, as the Spanish data protection authority (AEPD) requires.
class CookieBanner extends ConsumerWidget {
  const CookieBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cookieBannerVisibleProvider)) return const SizedBox.shrink();
    final consent = ref.read(cookieConsentProvider.notifier);
    final text = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Material(
              color: AppColors.cream,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Cookies', style: text.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Con tu permiso, usamos cookies de Google Analytics para '
                      'saber cómo se usa la tienda y mejorarla. No las usamos '
                      'para publicidad. Puedes cambiar tu elección cuando '
                      'quieras desde "Cookies", al pie de la página.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => launchUrl(
                            Env.sitePage('privacidad.html#cookies'),
                          ),
                          child: const Text('Más información'),
                        ),
                        OutlinedButton(
                          onPressed: consent.reject,
                          child: const Text('Rechazar'),
                        ),
                        FilledButton(
                          onPressed: consent.accept,
                          child: const Text('Aceptar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
