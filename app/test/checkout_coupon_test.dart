import 'dart:convert';

import 'package:dona_galleta/core/auth.dart';
import 'package:dona_galleta/core/money.dart';
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

/// What the API answers for each code at /api/checkout/coupon.
const _coupons = {
  'DESC10': {
    'code': 'DESC10',
    'description': '10 % en todo',
    'discount_type': 'percent',
    'amount_cents': null,
    'percent': 10,
  },
  'ENVIO': {
    'code': 'ENVIO',
    'description': '',
    'discount_type': 'free_shipping',
    'amount_cents': null,
    'percent': null,
  },
};

void main() {
  late List<Map<String, dynamic>> orders;

  Future<void> pumpCheckout(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    orders = [];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/api/checkout/coupon') {
          final coupon = _coupons[(body['code'] as String).toUpperCase()];
          return coupon == null
              ? http.Response(
                  '{"error": "This coupon has expired", "code": "coupon_expired"}',
                  409,
                )
              : http.Response(jsonEncode(coupon), 200);
        }
        orders.add(body);
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
            (ref) async => const ShopSettings(shippingFlatCents: 600),
          ),
          orderRepositoryProvider.overrideWithValue(OrderRepository(api)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> applyCode(WidgetTester tester, String code) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Código de descuento'),
      code,
    );
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndOrder(WidgetTester tester) async {
    await tester.enterText(field('Nombre y apellidos *'), 'Ana');
    if (field('Dirección *').evaluate().isNotEmpty) {
      await tester.enterText(field('Dirección *'), 'Calle Mayor 1');
      await tester.enterText(field('Código postal *'), '08001');
      await tester.enterText(field('Ciudad *'), 'Barcelona');
    }
    await tester.tap(find.text('Realizar pedido'));
    await tester.pumpAndSettle();
  }

  testWidgets('a percent coupon comes off products and shipping', (
    tester,
  ) async {
    await pumpCheckout(tester);
    expect(find.text(formatCents(2600)), findsOneWidget);

    await applyCode(tester, 'desc10');
    expect(find.text('Cupón DESC10 · -10 %'), findsOneWidget);
    expect(find.text('Descuento (DESC10)'), findsOneWidget);
    expect(find.text('-${formatCents(260)}'), findsOneWidget);
    expect(find.text(formatCents(2340)), findsOneWidget);

    await fillAndOrder(tester);
    expect(orders.single['coupon_code'], 'DESC10');

    // Removed, the total goes back and the order carries no code.
    await tester.tap(find.byTooltip('Quitar cupón'));
    await tester.pumpAndSettle();
    expect(find.text('Descuento (DESC10)'), findsNothing);
    expect(find.text(formatCents(2600)), findsOneWidget);
    await tester.tap(find.text('Realizar pedido'));
    await tester.pumpAndSettle();
    expect(orders.last.containsKey('coupon_code'), isFalse);
  });

  testWidgets('a code that cannot be used says why in Spanish', (tester) async {
    await pumpCheckout(tester);
    await applyCode(tester, 'VIEJO');
    expect(find.text('Ese código de descuento ha caducado.'), findsOneWidget);
    expect(find.textContaining('Descuento ('), findsNothing);
  });

  testWidgets('free shipping gives nothing on pickup and is not sent', (
    tester,
  ) async {
    await pumpCheckout(tester);
    await applyCode(tester, 'ENVIO');
    expect(find.text('Descuento (ENVIO)'), findsOneWidget);
    expect(
      find.text(formatCents(2000)),
      findsNWidgets(3),
    ); // line, subtotal, total

    await tester.tap(find.text('Recogida en tienda').first);
    await tester.pumpAndSettle();
    expect(find.text('Descuento (ENVIO)'), findsNothing);
    expect(find.textContaining('no cambia nada'), findsOneWidget);

    await fillAndOrder(tester);
    expect(orders.single['delivery_method'], 'pickup');
    expect(orders.single.containsKey('coupon_code'), isFalse);
  });
}
