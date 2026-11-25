import 'dart:convert';

import 'package:dona_galleta/core/money.dart';
import 'package:dona_galleta/features/admin/admin_settings_screen.dart';
import 'package:dona_galleta/features/admin/product_form_screen.dart';
import 'package:dona_galleta/features/orders/order_widgets.dart';
import 'package:dona_galleta/models/costs.dart';
import 'package:dona_galleta/models/order.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/models/shop_settings.dart';
import 'package:dona_galleta/repositories/admin_repository.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A ball in two sizes: its cost, supplier and box, and the big one's own cost.
final _product = {
  'id': 'p1',
  'name': 'Bola',
  'slug': 'bola',
  'base_price_cents': 800,
  'is_active': true,
  'category_ids': <String>[],
  'cost_cents': 300,
  'supplier_id': 's1',
  'box_size': 'M',
  'product_variants': [
    {
      'id': 'v8',
      'product_id': 'p1',
      'name': '8 cm',
      'options': {'Tamaño': '8 cm'},
      'position': 0,
      'cost_cents': null,
    },
    {
      'id': 'v10',
      'product_id': 'p1',
      'name': '10 cm',
      'options': {'Tamaño': '10 cm'},
      'price_cents': 1000,
      'position': 1,
      'cost_cents': 450,
    },
  ],
  'product_images': <Map<String, dynamic>>[],
};

const _boxes = CostSettings(boxSCents: 25, boxMCents: 50, boxLCents: 100);

final _suppliers = [
  {'id': 's1', 'name': 'Telas Ana', 'transport_cents': 300, 'products': 2},
  {'id': 's2', 'name': 'Cajas Sur', 'transport_cents': 150, 'products': 0},
];

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Taps [finder] after scrolling it into view.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('models', () {
    test('a product reads and sends its costs', () {
      final product = Product.fromJson(_product);
      expect(product.costCents, 300);
      expect(product.supplierId, 's1');
      expect(product.boxSize, BoxSize.m);
      expect(product.variants.last.costCents, 450);
      expect(product.variants.first.costCents, isNull);
      expect(product.toJson(), containsPair('box_size', 'M'));
      expect(
        VariantDraft.fromVariant(product.variants.last).toJson(),
        containsPair('cost_cents', 450),
      );
    });

    test('the store product has no costs', () {
      final product = Product.fromJson({..._product}..remove('cost_cents'));
      expect(product.costCents, isNull);
    });

    test('an article cost says what it is made of', () {
      final cost = OrderItemCost.fromJson({
        'order_item_id': 'i1',
        'quantity': 3,
        'unit_cost_cents': 200,
        'box_size': 'M',
        'box_cents': 50,
        'line_cost_cents': 650,
      });
      expect(
        cost.breakdown,
        '3 × ${formatCents(200)} + caja M ${formatCents(50)}',
      );
      final none = OrderItemCost.fromJson({
        'order_item_id': 'i2',
        'quantity': 1,
        'unit_cost_cents': null,
        'line_cost_cents': 0,
      });
      expect(none.breakdown, 'Sin coste');
    });
  });

  group('product form', () {
    late List<Map<String, dynamic>> saved;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      saved = [];
      final api = ApiClient(
        baseUrl: 'https://shop.test',
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            saved.add(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return _json(_product);
        }),
      );
      final router = GoRouter(
        initialLocation: '/admin/products/p1',
        routes: [
          GoRoute(
            path: '/admin/products/:id',
            builder: (_, state) => Scaffold(
              body: ProductFormScreen(productId: state.pathParameters['id']),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(AdminRepository(api)),
            adminCategoriesProvider.overrideWith((ref) async => []),
            suppliersProvider.overrideWith(
              (ref) async => [for (final s in _suppliers) Supplier.fromJson(s)],
            ),
            costSettingsProvider.overrideWith((ref) async => _boxes),
            adminProductProvider.overrideWith(
              (ref, id) async => Product.fromJson(_product),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    testWidgets('cost sits right of the price; supplier and box are shown', (
      tester,
    ) async {
      await pump(tester);
      final price = tester.getTopLeft(field('Precio (€) *'));
      final cost = tester.getTopLeft(field('Coste (€)').first);
      expect(cost.dx, greaterThan(price.dx));
      expect(cost.dy, price.dy);
      expect(find.text('3,00'), findsOneWidget);
      expect(find.text('Telas Ana'), findsOneWidget);
      expect(find.text('M · ${formatCents(50)}'), findsOneWidget);

      // Each variant has its cost right of its price.
      final variantPrice = tester.getCenter(field('Precio (€)').last);
      final variantCost = tester.getCenter(field('Coste (€)').last);
      expect(variantCost.dx, greaterThan(variantPrice.dx));
      expect(variantCost.dy, variantPrice.dy);
      expect(find.text('4,50'), findsOneWidget);
    });

    testWidgets('saving sends the costs, supplier and box', (tester) async {
      await pump(tester);
      await tester.enterText(field('Coste (€)').first, '3,50');
      await tester.enterText(field('Coste (€)').at(1), '2');
      await _tap(tester, find.text('Telas Ana'));
      await _tap(tester, find.text('Cajas Sur').last);
      await _tap(tester, find.text('M · ${formatCents(50)}'));
      await _tap(tester, find.text('L · ${formatCents(100)}').last);
      await _tap(tester, find.text('Guardar cambios'));

      final body = saved.single;
      expect(body['cost_cents'], 350);
      expect(body['supplier_id'], 's2');
      expect(body['box_size'], 'L');
      final variants = (body['variants'] as List).cast<Map<String, dynamic>>();
      expect(variants.map((v) => v['cost_cents']), [200, 450]);
    });
  });

  group('Ajustes', () {
    late List<http.Request> writes;
    late List<Map<String, dynamic>> suppliers;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      writes = [];
      suppliers = [for (final s in _suppliers) Map.of(s)];
      final api = ApiClient(
        baseUrl: 'https://shop.test',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (request.method != 'GET') writes.add(request);
          if (path == '/api/admin/cost-settings') {
            return _json(
              request.method == 'PUT'
                  ? jsonDecode(request.body)
                  : _boxes.toJson(),
            );
          }
          if (path == '/api/admin/suppliers' && request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            suppliers.add({...body, 'id': 's3', 'products': 0});
            return _json({...body, 'id': 's3'}, 201);
          }
          if (path.startsWith('/api/admin/suppliers/') &&
              request.method == 'DELETE') {
            suppliers.removeWhere((s) => path.endsWith('/${s['id']}'));
            return http.Response('', 204);
          }
          if (path == '/api/admin/suppliers') return _json(suppliers);
          return _json({'error': 'unexpected $path'}, 500);
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(AdminRepository(api)),
            shopSettingsProvider.overrideWith(
              (ref) async => const ShopSettings(shippingFlatCents: 495),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: AdminSettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('box prices start at 0,25 / 0,50 / 1,00 and are saved', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('0,25'), findsOneWidget);
      expect(find.text('0,50'), findsOneWidget);
      expect(find.text('1,00'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Caja M (€)'),
        '0,60',
      );
      await _tap(tester, find.text('Guardar precios'));
      expect(writes.single.method, 'PUT');
      expect(jsonDecode(writes.single.body), {
        'box_s_cents': 25,
        'box_m_cents': 60,
        'box_l_cents': 100,
      });
      expect(find.text('Precios de las cajas guardados'), findsOneWidget);
    });

    testWidgets('suppliers are listed, added and deleted', (tester) async {
      await pump(tester);
      expect(find.text('Telas Ana'), findsOneWidget);
      expect(
        find.text('Transporte ${formatCents(300)} · 2 productos'),
        findsOneWidget,
      );

      await _tap(tester, find.text('Añadir proveedor'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre *'),
        'Lazos Pepa',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Transporte (€) *'),
        '2,5',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Guardar').last);
      expect(jsonDecode(writes.last.body), {
        'name': 'Lazos Pepa',
        'transport_cents': 250,
      });
      expect(find.text('Lazos Pepa'), findsOneWidget);

      await _tap(tester, find.byTooltip('Eliminar Telas Ana'));
      expect(
        find.textContaining('Los 2 productos que lo tienen'),
        findsOneWidget,
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Eliminar'));
      expect(writes.last.method, 'DELETE');
      expect(writes.last.url.path, '/api/admin/suppliers/s1');
      expect(find.text('Telas Ana'), findsNothing);
    });
  });

  group('order page', () {
    final order = Order.fromJson({
      'id': 'o1',
      'order_number': 1004,
      'status': 'processing',
      'subtotal_cents': 2600,
      'shipping_cents': 0,
      'total_cents': 2600,
      'shipping_name': 'Ana López',
      'delivery_method': 'pickup',
      'shipping_address': {},
      'created_at': '2026-11-25T10:32:00Z',
      'order_items': [
        {
          'id': 'i1',
          'product_name': 'Bola',
          'variant_name': 'Default',
          'unit_price_cents': 800,
          'quantity': 2,
          'line_total_cents': 1600,
        },
        {
          'id': 'i2',
          'product_name': 'Lazo',
          'variant_name': 'Default',
          'unit_price_cents': 1000,
          'quantity': 1,
          'line_total_cents': 1000,
        },
      ],
      'order_status_history': [],
    });
    final costs = OrderCosts.fromJson({
      'items': [
        {
          'order_item_id': 'i1',
          'quantity': 2,
          'unit_cost_cents': 300,
          'box_size': 'M',
          'box_cents': 50,
          'supplier_name': 'Telas Ana',
          'line_cost_cents': 650,
        },
        {
          'order_item_id': 'i2',
          'quantity': 1,
          'unit_cost_cents': 200,
          'box_size': null,
          'box_cents': 0,
          'supplier_name': 'Telas Ana',
          'line_cost_cents': 200,
        },
      ],
      'suppliers': [
        {'name': 'Telas Ana', 'transport_cents': 300},
      ],
      'items_cost_cents': 850,
      'transport_cents': 300,
      'total_cost_cents': 1150,
      'missing_costs': false,
      'estimated': false,
    });

    Future<void> pump(WidgetTester tester, {OrderCosts? costs}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderSummary(order: order, costs: costs),
            ),
          ),
        ),
      );
    }

    testWidgets('each article shows its cost; the total cost follows', (
      tester,
    ) async {
      await pump(tester, costs: costs);
      expect(
        find.text(
          'Coste: ${formatCents(650)} '
          '(2 × ${formatCents(300)} + caja M ${formatCents(50)})',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Coste: ${formatCents(200)} (1 × ${formatCents(200)})'),
        findsOneWidget,
      );
      expect(find.text('Coste total'), findsOneWidget);
      expect(find.text(formatCents(1150)), findsOneWidget);
      // One transport for the two articles of the same supplier.
      expect(find.text('Transporte (Telas Ana)'), findsOneWidget);
      // Right under the total.
      final total = tester.getTopLeft(find.text('Total'));
      final cost = tester.getTopLeft(find.text('Coste total'));
      expect(cost.dy, greaterThan(total.dy));
    });

    testWidgets('customers see no costs', (tester) async {
      await pump(tester);
      expect(find.textContaining('Coste'), findsNothing);
    });
  });
}
