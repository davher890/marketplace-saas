import 'package:dona_galleta/features/admin/admin_orders_screen.dart';
import 'package:dona_galleta/models/order.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Order _order() => Order.fromJson({
  'id': 'o1',
  'order_number': 1004,
  'status': 'paid',
  'subtotal_cents': 6800,
  'shipping_cents': 600,
  'total_cents': 7400,
  'shipping_name': 'Ana López',
  'contact_email': 'ana@example.com',
  'shipping_address': {
    'line1': 'Calle Mayor 1',
    'city': 'Madrid',
    'postal_code': '28001',
  },
  'created_at': '2026-11-10T10:32:00Z',
  'order_items': [
    {
      'id': 'i1',
      'product_name': 'Pack taza y manta',
      'variant_name': 'Rosa',
      'unit_price_cents': 3000,
      'quantity': 2,
      'line_total_cents': 6000,
      'customization': 'Color del lazo: Azul · Lucía',
    },
    {
      'id': 'i2',
      'product_name': 'Bola de madera',
      'variant_name': 'Default',
      'unit_price_cents': 800,
      'quantity': 1,
      'line_total_cents': 800,
      'customization': '',
    },
  ],
  'order_status_history': [],
});

void main() {
  test('the supplier text has units, variants and personalisation only', () {
    final text = _order().supplierText;
    expect(
      text,
      'Pedido #1004\n'
      '\n'
      '- 2 × Pack taza y manta · Rosa\n'
      '  Personalización: Color del lazo: Azul · Lucía\n'
      '- 1 × Bola de madera',
    );
    // Nothing the supplier doesn't need.
    expect(text, isNot(contains('€')));
    expect(text, isNot(contains('Ana')));
    expect(text, isNot(contains('Madrid')));
  });

  testWidgets('"Copiar encargo" puts it on the clipboard', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
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
        overrides: [orderProvider.overrideWith((ref, id) async => _order())],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copiar encargo'));
    await tester.pumpAndSettle();
    expect(copied, _order().supplierText);
    expect(find.textContaining('Encargo copiado'), findsOneWidget);
  });
}
