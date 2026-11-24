import 'dart:convert';

import 'package:dona_galleta/features/admin/admin_coupons_screen.dart';
import 'package:dona_galleta/features/admin/admin_shell.dart';
import 'package:dona_galleta/models/coupon.dart';
import 'package:dona_galleta/repositories/admin_repository.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _coupons = [
  Coupon(
    id: 'a',
    code: 'NAVIDAD10',
    description: '10 % en Navidad',
    startsOn: DateTime(2026, 11, 20),
    endsOn: DateTime(2026, 12, 31),
    usage: CouponUsage.oncePerUser,
    discountType: DiscountType.percent,
    percent: 10,
    uses: 2,
  ),
  Coupon(
    id: 'b',
    code: 'REYES',
    startsOn: DateTime(2027, 1, 1),
    endsOn: DateTime(2027, 1, 6),
    discountType: DiscountType.freeShipping,
    status: CouponStatus.scheduled,
  ),
  Coupon(
    id: 'c',
    code: 'VERANO',
    startsOn: DateTime(2026, 7, 1),
    endsOn: DateTime(2026, 8, 31),
    discountType: DiscountType.amount,
    amountCents: 500,
    isActive: false,
    status: CouponStatus.disabled,
    uses: 1,
  ),
];

void main() {
  late List<http.Request> requests;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Pixel-like phone with a slightly enlarged system font.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    requests = [];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({...body, 'id': 'a', 'status': 'active', 'uses': 2}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminCouponsProvider.overrideWith((ref) async => _coupons),
          adminRepositoryProvider.overrideWithValue(AdminRepository(api)),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.15)),
            child: child!,
          ),
          home: const Scaffold(body: AdminCouponsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps [finder] after scrolling it into view (the dialog scrolls on a phone).
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('lists active coupons apart from the rest, fitting a phone', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Activos (1)'), findsOneWidget);
    expect(find.text('No activos (2)'), findsOneWidget);
    expect(
      find.text(
        'Del 20/11/2026 al 31/12/2026 · Una vez por usuario · Usado en 2 pedidos',
      ),
      findsOneWidget,
    );
    expect(find.text('Programado'), findsOneWidget);
    expect(find.text('Desactivado'), findsOneWidget);
    expect(find.text('Envío gratis'), findsOneWidget);
    // The list order follows the sections: the active one first.
    expect(
      tester.getTopLeft(find.text('NAVIDAD10')).dy,
      lessThan(tester.getTopLeft(find.text('REYES')).dy),
    );
  });

  testWidgets('the switch turns a coupon on or off', (tester) async {
    await pumpScreen(tester);
    await tapVisible(tester, find.byType(Switch).last);
    expect(requests.single.method, 'PATCH');
    expect(requests.single.url.path, '/api/admin/coupons/c');
    expect(jsonDecode(requests.single.body), {'is_active': true});
  });

  testWidgets('editing a coupon saves every field', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('NAVIDAD10'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Editar cupón'), findsOneWidget);

    await tapVisible(tester, find.text('Importe (€)'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Euros de descuento *'),
      '7,5',
    );
    await tapVisible(tester, find.text('Una vez por compra'));
    await tapVisible(tester, find.text('Guardar'));

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/admin/coupons/a');
    expect(jsonDecode(requests.single.body), {
      'code': 'NAVIDAD10',
      'description': '10 % en Navidad',
      'starts_on': '2026-11-20',
      'ends_on': '2026-12-31',
      'usage': 'once_per_order',
      'discount_type': 'amount',
      'amount_cents': 750,
      'percent': null,
      'is_active': true,
    });
    expect(find.text('Cupón guardado.'), findsOneWidget);
  });

  testWidgets('a new coupon needs a code, dates and a value', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Nuevo cupón'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código *'),
      'navidad 2!',
    );
    expect(find.text('NAVIDAD2'), findsOneWidget);

    await tapVisible(tester, find.text('Guardar'));
    expect(find.text('Elige las fechas'), findsOneWidget);
    expect(find.text('Importe no válido'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('"Cupones" is in the admin menu, which still fits a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/admin/orders',
      routes: [
        ShellRoute(
          builder: (_, _, child) => AdminShell(child: child),
          routes: [
            GoRoute(
              path: '/admin/orders',
              builder: (_, _) => const Text('Lista de pedidos'),
            ),
            GoRoute(
              path: '/admin/coupons',
              builder: (_, _) => const AdminCouponsScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminProductsProvider.overrideWith((ref) async => []),
          adminCouponsProvider.overrideWith((ref) async => _coupons),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cupones'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/admin/coupons');
    expect(find.text('Activos (1)'), findsOneWidget);
  });
}
