import 'package:dona_galleta/core/analytics/cookie_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the page's Tag Manager loader.
class _FakeStore implements AnalyticsConsentStore {
  _FakeStore({this.available = true, this.stored});

  @override
  final bool available;

  @override
  String? stored;

  final saved = <bool>[];

  @override
  void save({required bool granted}) {
    saved.add(granted);
    stored = granted ? 'granted' : 'denied';
  }
}

void main() {
  late _FakeStore store;

  Future<ProviderContainer> pumpBanner(
    WidgetTester tester, {
    bool available = true,
    String? stored,
  }) async {
    store = _FakeStore(available: available, stored: stored);
    final container = ProviderContainer(
      overrides: [analyticsConsentStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [CookieBanner()])),
        ),
      ),
    );
    return container;
  }

  testWidgets('asks first-time visitors and remembers acceptance', (
    tester,
  ) async {
    final container = await pumpBanner(tester);
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Rechazar'), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.pump();
    expect(store.saved, [true]);
    expect(container.read(cookieConsentProvider), CookieConsent.granted);
    expect(find.text('Aceptar'), findsNothing);
  });

  testWidgets('rejecting is as easy as accepting', (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.text('Rechazar'));
    await tester.pump();
    expect(store.saved, [false]);
    expect(find.text('Rechazar'), findsNothing);
  });

  testWidgets('a previous choice is respected, and can be changed', (
    tester,
  ) async {
    final container = await pumpBanner(tester, stored: 'granted');
    expect(find.text('Aceptar'), findsNothing);
    expect(container.read(cookieConsentProvider), CookieConsent.granted);

    container.read(cookieConsentProvider.notifier).reopen();
    await tester.pump();
    expect(find.text('Rechazar'), findsOneWidget);
    expect(store.saved, isEmpty, reason: 'nothing changes until they choose');

    await tester.tap(find.text('Rechazar'));
    await tester.pump();
    expect(store.saved, [false]);
  });

  testWidgets('no banner when Tag Manager is not configured', (tester) async {
    final container = await pumpBanner(tester, available: false);
    expect(find.text('Aceptar'), findsNothing);
    container.read(cookieConsentProvider.notifier).reopen();
    await tester.pump();
    expect(find.text('Aceptar'), findsNothing);
    expect(container.read(cookieConsentProvider), CookieConsent.denied);
  });
}
