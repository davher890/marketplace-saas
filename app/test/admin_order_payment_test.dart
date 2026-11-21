import 'dart:convert';

import 'package:dona_galleta/features/admin/admin_orders_screen.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The fake API's copy of order o1, updated by PATCH requests.
Map<String, dynamic> _order({String? paidAt}) => {
  'id': 'o1',
  'order_number': 1004,
  'status': 'received',
  'subtotal_cents': 2400,
  'shipping_cents': 0,
  'total_cents': 2400,
  'delivery_method': 'pickup',
  'shipping_name': 'Ana',
  'shipping_address': {},
  'paid_at': paidAt,
  'created_at': '2026-11-20T16:00:00.000Z',
  'order_items': [],
  'order_status_history': [],
};

void main() {
  testWidgets('the admin marks an order as paid and back', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var stored = _order();
    final patches = <Object?>[];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          patches.add(body);
          stored = _order(
            paidAt: body['paid'] == true ? '2026-11-21T10:30:00.000Z' : null,
          );
        }
        return http.Response(
          jsonEncode(stored),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final router = GoRouter(
      initialLocation: '/admin/orders/o1',
      routes: [
        GoRoute(
          path: '/admin/orders/:id',
          builder: (_, state) => Scaffold(
            body: AdminOrderScreen(orderId: state.pathParameters['id']!),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWith((ref) => OrderRepository(api)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Payment is not one of the statuses any more.
    expect(find.widgetWithText(ChoiceChip, 'Pagado'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Recibido'), findsOneWidget);
    final paidSwitch = find.widgetWithText(SwitchListTile, 'Pagado');
    expect(tester.widget<SwitchListTile>(paidSwitch).value, isFalse);
    expect(find.textContaining('se avisa al cliente'), findsOneWidget);

    await tester.tap(paidSwitch);
    await tester.pumpAndSettle();
    expect(patches, [
      {'paid': true},
    ]);
    expect(tester.widget<SwitchListTile>(paidSwitch).value, isTrue);
    expect(find.textContaining('Desde el 21/11/2026'), findsOneWidget);

    await tester.tap(paidSwitch);
    await tester.pumpAndSettle();
    expect(patches.last, {'paid': false});
    expect(tester.widget<SwitchListTile>(paidSwitch).value, isFalse);
  });
}
