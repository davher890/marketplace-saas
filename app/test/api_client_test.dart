import 'dart:convert';

import 'package:dona_galleta/models/order.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/cart_repository.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final db = SupabaseClient('http://localhost:54321', 'test-key');

  ApiClient clientReturning(
    int status,
    Object? body, {
    void Function(http.Request)? onRequest,
  }) => ApiClient(
    db,
    baseUrl: 'https://shop.test',
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  test('sends JSON with method, path and query', () async {
    late http.Request sent;
    final api = clientReturning(200, [], onRequest: (r) => sent = r);
    await api.get('/api/admin/orders', query: {'status': 'paid'});
    expect(sent.method, 'GET');
    expect(
      sent.url.toString(),
      'https://shop.test/api/admin/orders?status=paid',
    );

    await api.patch('/api/cart/items/1', {'quantity': 2});
    expect(sent.method, 'PATCH');
    expect(jsonDecode(sent.body), {'quantity': 2});
  });

  test('turns API errors into ApiException with the server message', () async {
    final api = clientReturning(409, {'error': 'Only 2 left of "Cojín nube"'});
    await expectLater(
      api.post('/api/cart/items', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('Only 2 left')),
      ),
    );
  });

  test('204 responses decode to null', () async {
    expect(
      await clientReturning(204, null).delete('/api/admin/images/1'),
      isNull,
    );
  });

  test('parses the cart returned by the API', () async {
    final api = clientReturning(200, {
      'items': [
        {
          'id': 'c1',
          'quantity': 2,
          'customization': 'Lucía',
          'unit_price_cents': 1200,
          'product_variants': {
            'id': 'v1',
            'product_id': 'p1',
            'name': 'Rosa',
            'options': {'Color': 'Rosa'},
            'price_cents': null,
            'stock': null,
            'products': {
              'id': 'p1',
              'name': 'Chupetero',
              'slug': 'chupetero',
              'base_price_cents': 1200,
              'is_customizable': true,
              'product_images': [],
            },
          },
        },
      ],
      'item_count': 2,
      'subtotal_cents': 2400,
    });
    final cart = await CartRepository(api).fetchCart();
    expect(cart.items.single.customization, 'Lucía');
    expect(cart.items.single.product.isCustomizable, isTrue);
    expect(cart.subtotalCents, 2400);
  });

  test('checkout sends snake_case fields and parses the order', () async {
    late http.Request sent;
    final api = clientReturning(201, {
      'order': {
        'id': 'o1',
        'order_number': 1000,
        'status': 'pending',
        'subtotal_cents': 2400,
        'shipping_cents': 495,
        'total_cents': 2895,
        'shipping_name': 'Ana',
        'shipping_address': {
          'line1': 'Calle 1',
          'city': 'Madrid',
          'postal_code': '28001',
        },
        'created_at': '2026-11-04T16:00:00.000Z',
        'order_items': [],
        'order_status_history': [
          {
            'from_status': null,
            'to_status': 'pending',
            'created_at': '2026-11-04T16:00:00.123456+00:00',
          },
        ],
      },
    }, onRequest: (r) => sent = r);

    final order = await OrderRepository(api).checkout(
      const CheckoutRequest(
        shippingName: 'Ana',
        shippingAddress: ShippingAddress(
          line1: 'Calle 1',
          city: 'Madrid',
          postalCode: '28001',
        ),
      ),
    );

    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['shipping_name'], 'Ana');
    expect(body['shipping_address']['postal_code'], '28001');
    expect(order.orderNumber, 1000);
    expect(order.status, OrderStatus.pending);
    expect(order.history.single.toStatus, OrderStatus.pending);
  });
}
