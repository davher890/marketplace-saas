import 'dart:convert';

import 'package:dona_galleta/core/auth.dart';
import 'package:dona_galleta/core/money.dart';
import 'package:dona_galleta/core/online_payment.dart';
import 'package:dona_galleta/features/checkout/checkout_screen.dart';
import 'package:dona_galleta/models/cart.dart';
import 'package:dona_galleta/models/shop_settings.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/cart_repository.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A cart with one 20 € line.
class _FixedCart extends CartNotifier {
  @override
  Future<Cart> build() async => Cart([
    CartItem.fromJson({
      'id': 'c1',
      'quantity': 1,
      'customization': '',
      'product_variants': {
        'id': 'v1',
        'product_id': 'p1',
        'name': 'Default',
        'options': {},
        'price_cents': null,
        'products': {
          'id': 'p1',
          'name': 'Bola',
          'slug': 'bola',
          'base_price_cents': 2000,
          'product_images': [],
        },
      },
    }),
  ]);
}

void main() {
  late List<Map<String, dynamic>> orders;

  Future<void> pumpCheckout(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    orders = [];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        orders.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"error": "stop here"}', 500);
      }),
    );
    final router = GoRouter(
      initialLocation: '/checkout',
      routes: [
        GoRoute(
          path: '/checkout',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: CheckoutScreen()),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AuthUser(id: 'u1', email: 'ana@example.com'),
          ),
          cartProvider.overrideWith(_FixedCart.new),
          shopSettingsProvider.overrideWith(
            (ref) async => const ShopSettings(
              shippingFlatCents: 600,
              shippingMadridCents: 500,
            ),
          ),
          orderRepositoryProvider.overrideWithValue(OrderRepository(api)),
          canPayOnlineProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('shipping follows the postal code', (tester) async {
    await pumpCheckout(tester);
    expect(find.text(formatCents(600)), findsOneWidget);
    expect(find.text(formatCents(2600)), findsOneWidget);

    await tester.enterText(field('Código postal *'), '28010');
    await tester.pumpAndSettle();
    expect(find.text(formatCents(500)), findsOneWidget);
    expect(find.text(formatCents(2500)), findsOneWidget);
  });

  testWidgets('store pickup is free and asks for no address', (tester) async {
    await pumpCheckout(tester);
    await tester.tap(find.text('Recogida en tienda').first);
    await tester.pumpAndSettle();

    expect(field('Dirección *'), findsNothing);
    expect(find.text('Gratis'), findsOneWidget);
    expect(
      find.text(formatCents(2000)),
      findsNWidgets(3),
    ); // line, subtotal, total

    await tester.enterText(field('Nombre y apellidos *'), 'Ana');
    await tester.tap(find.text('Realizar pedido'));
    await tester.pumpAndSettle();

    expect(orders.single['delivery_method'], 'pickup');
    expect(orders.single.containsKey('shipping_address'), isFalse);
  });

  testWidgets('only Spanish postal codes are accepted', (tester) async {
    await pumpCheckout(tester);
    await tester.enterText(field('Nombre y apellidos *'), 'Ana');
    await tester.enterText(field('Dirección *'), 'Calle Mayor 1');
    await tester.enterText(field('Ciudad *'), 'Madrid');

    await tester.enterText(field('Código postal *'), '53001');
    await tester.tap(find.text('Realizar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Código postal no válido'), findsOneWidget);
    expect(orders, isEmpty);

    // Letters and a sixth digit are not even typed.
    await tester.enterText(field('Código postal *'), '');
    await tester.enterText(field('Código postal *'), '28a0101');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(field('Código postal *')).controller!.text,
      '28010',
    );

    await tester.tap(find.text('Realizar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Código postal no válido'), findsNothing);
    expect(orders.single['shipping_address']['postal_code'], '28010');
  });
}
