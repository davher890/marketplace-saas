import 'dart:convert';

import 'package:dona_galleta/core/auth.dart';
import 'package:dona_galleta/core/online_payment.dart';
import 'package:dona_galleta/features/checkout/checkout_screen.dart';
import 'package:dona_galleta/features/orders/my_orders_screen.dart';
import 'package:dona_galleta/models/cart.dart';
import 'package:dona_galleta/models/shop_settings.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/cart_repository.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:dona_galleta/repositories/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _stripeUrl = 'https://checkout.stripe.test/c/pay/cs_test_1';

Map<String, dynamic> _order({bool paid = false, String status = 'received'}) =>
    {
      'id': 'o1',
      'order_number': 1004,
      'status': status,
      'subtotal_cents': 2000,
      'shipping_cents': 0,
      'total_cents': 2000,
      'delivery_method': 'pickup',
      'shipping_name': 'Ana',
      'shipping_address': {},
      'paid_at': paid ? '2026-11-21T10:30:00.000Z' : null,
      'paid_via': paid ? 'stripe' : null,
      'created_at': '2026-11-21T10:00:00.000Z',
      'order_items': [],
      'order_status_history': [],
    };

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

/// Fake API: checkout creates order o1, /pay returns a Stripe URL, and GET
/// returns the order (paid once [paidAfterGets] reads have happened).
class _FakeApi {
  _FakeApi({this.paidAfterGets});

  final int? paidAfterGets;
  final requests = <String>[];
  int _gets = 0;

  ApiClient get client => ApiClient(
    baseUrl: 'https://shop.test',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      final Object body;
      if (request.url.path == '/api/orders/o1/pay') {
        body = {'url': _stripeUrl};
      } else if (request.url.path == '/api/checkout') {
        body = {'order': _order()};
      } else {
        _gets++;
        body = _order(paid: paidAfterGets != null && _gets > paidAfterGets!);
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  late List<Uri> opened;

  Future<GoRouter> pump(
    WidgetTester tester, {
    required String location,
    required bool canPay,
    required _FakeApi api,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    opened = [];
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/checkout',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: CheckoutScreen()),
          ),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, state) => Scaffold(
            body: SingleChildScrollView(
              child: OrderDetailScreen(
                orderId: state.pathParameters['id']!,
                justPlaced: state.uri.queryParameters['placed'] == '1',
                paymentReturn: PaymentReturn.fromUrl(
                  state.uri.queryParameters['pago'],
                ),
              ),
            ),
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
          canPayOnlineProvider.overrideWith((ref) async => canPay),
          orderRepositoryProvider.overrideWithValue(
            OrderRepository(api.client),
          ),
          paymentPageOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The "confirming" spinner never settles: pump just enough frames.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }
    return router;
  }

  test('online payment is for admins until the shop opens it', () async {
    Future<bool> canPay({required bool public, required bool admin}) {
      final container = ProviderContainer(
        overrides: [
          shopSettingsProvider.overrideWith(
            (ref) async =>
                ShopSettings(shippingFlatCents: 0, onlinePaymentPublic: public),
          ),
          isAdminProvider.overrideWith((ref) async => admin),
        ],
      );
      addTearDown(container.dispose);
      return container.read(canPayOnlineProvider.future);
    }

    expect(await canPay(public: false, admin: false), isFalse);
    expect(await canPay(public: false, admin: true), isTrue);
    expect(await canPay(public: true, admin: false), isTrue);
    expect(
      ShopSettings.fromJson({
        'online_payment_public': true,
      }).toJson()['online_payment_public'],
      isTrue,
    );
  });

  group('checkout', () {
    Future<void> fillAndPlace(WidgetTester tester, String button) async {
      await tester.tap(find.text('Recogida en tienda').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre y apellidos *'),
        'Ana',
      );
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    testWidgets('customers without online payment see no payment choice', (
      tester,
    ) async {
      final api = _FakeApi();
      final router = await pump(
        tester,
        location: '/checkout',
        canPay: false,
        api: api,
      );
      expect(find.text('Pagar ahora'), findsNothing);
      await fillAndPlace(tester, 'Realizar pedido');
      expect(api.requests.first, 'POST /api/checkout');
      expect(api.requests, isNot(contains('POST /api/orders/o1/pay')));
      expect(opened, isEmpty);
      expect(router.state.uri.toString(), '/orders/o1?placed=1');
    });

    testWidgets('paying now places the order and opens Stripe', (tester) async {
      final api = _FakeApi();
      await pump(tester, location: '/checkout', canPay: true, api: api);
      expect(find.text('Pagar ahora'), findsOneWidget);
      await fillAndPlace(tester, 'Realizar pedido y pagar');
      expect(api.requests, ['POST /api/checkout', 'POST /api/orders/o1/pay']);
      expect(opened, [Uri.parse(_stripeUrl)]);
    });

    testWidgets('agreeing the payment with the shop skips Stripe', (
      tester,
    ) async {
      final api = _FakeApi();
      final router = await pump(
        tester,
        location: '/checkout',
        canPay: true,
        api: api,
      );
      await tester.tap(find.text('Acordarlo con la tienda'));
      await tester.pumpAndSettle();
      await fillAndPlace(tester, 'Realizar pedido');
      expect(api.requests.first, 'POST /api/checkout');
      expect(api.requests, isNot(contains('POST /api/orders/o1/pay')));
      expect(opened, isEmpty);
      expect(router.state.uri.toString(), '/orders/o1?placed=1');
    });
  });

  group('order page', () {
    testWidgets('unpaid order: pay button only with online payment', (
      tester,
    ) async {
      await pump(
        tester,
        location: '/orders/o1',
        canPay: false,
        api: _FakeApi(),
      );
      expect(find.textContaining('Pagar ahora'), findsNothing);
    });

    testWidgets('the pay button opens Stripe', (tester) async {
      final api = _FakeApi();
      await pump(tester, location: '/orders/o1', canPay: true, api: api);
      await tester.tap(find.textContaining('Pagar ahora'));
      await tester.pumpAndSettle();
      expect(api.requests.last, 'POST /api/orders/o1/pay');
      expect(opened, [Uri.parse(_stripeUrl)]);
    });

    testWidgets('back from Stripe, waits until the payment is confirmed', (
      tester,
    ) async {
      await pump(
        tester,
        location: '/orders/o1?pago=ok',
        canPay: true,
        api: _FakeApi(paidAfterGets: 2),
        settle: false,
      );
      expect(find.text('Estamos confirmando tu pago…'), findsOneWidget);
      expect(find.textContaining('Pagar ahora'), findsOneWidget);

      // Two more reloads: the second one finds it paid.
      for (var i = 0; i < 3; i++) {
        await tester.pump(OrderDetailScreen.pollInterval);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(find.text('¡Pago recibido, gracias!'), findsOneWidget);
      expect(find.textContaining('Pagar ahora'), findsNothing);
      expect(find.text('Pagado'), findsOneWidget);
    });

    testWidgets('a cancelled payment says the order is kept', (tester) async {
      await pump(
        tester,
        location: '/orders/o1?pago=cancelado',
        canPay: true,
        api: _FakeApi(),
      );
      expect(find.text('No se ha completado el pago'), findsOneWidget);
      expect(find.textContaining('Pagar ahora'), findsOneWidget);
    });
  });
}
