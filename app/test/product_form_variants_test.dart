import 'dart:convert';

import 'package:dona_galleta/features/admin/product_form_screen.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/repositories/admin_repository.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A ball sold in two sizes, the bigger one dearer.
final _product = {
  'id': 'p1',
  'name': 'Bola',
  'slug': 'bola',
  'base_price_cents': 800,
  'is_active': true,
  'category_ids': <String>[],
  'product_variants': [
    {
      'id': 'v8',
      'product_id': 'p1',
      'name': '8 cm',
      'options': {'Tamaño': '8 cm'},
      'stock': 3,
      'position': 0,
    },
    {
      'id': 'v10',
      'product_id': 'p1',
      'name': '10 cm',
      'options': {'Tamaño': '10 cm'},
      'price_cents': 1000,
      'position': 1,
    },
  ],
  'product_images': <Map<String, dynamic>>[],
};

void main() {
  late List<Map<String, dynamic>> saved;

  Future<void> pumpEditor(WidgetTester tester) async {
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
        return http.Response(jsonEncode(_product), 200);
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

  Future<List<Map<String, dynamic>>> save(WidgetTester tester) async {
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    return (saved.single['variants'] as List).cast<Map<String, dynamic>>();
  }

  testWidgets('adding an option creates every combination', (tester) async {
    await pumpEditor(tester);
    expect(find.text('8 cm'), findsOneWidget);
    expect(find.text('10 cm'), findsOneWidget);

    await tester.tap(find.text('Añadir opción'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Opción').last, 'Material');
    await tester.enterText(
      field('Valores, separados por comas').last,
      'Cristal, Madera',
    );
    await tester.pumpAndSettle();
    expect(find.text('10 cm · Madera'), findsOneWidget);

    final variants = await save(tester);
    expect(variants.map((v) => v['name']), [
      '8 cm · Cristal',
      '8 cm · Madera',
      '10 cm · Cristal',
      '10 cm · Madera',
    ]);
    // The existing variants keep their id, price and stock.
    expect(variants[0]['id'], 'v8');
    expect(variants[0]['stock'], 3);
    expect(variants[0]['options'], {'Tamaño': '8 cm', 'Material': 'Cristal'});
    expect(variants[1].containsKey('id'), isFalse);
    expect(variants[2]['id'], 'v10');
    expect(variants[2]['price_cents'], 1000);
  });

  testWidgets('renaming a value keeps its variant', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(
      field('Valores, separados por comas').first,
      '8 cm, 12 cm',
    );
    await tester.pumpAndSettle();

    final variants = await save(tester);
    expect(variants.map((v) => v['id']), ['v8', 'v10']);
    expect(variants[1]['options'], {'Tamaño': '12 cm'});
    expect(variants[1]['price_cents'], 1000);
  });

  testWidgets('removing every option leaves one plain variant', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Quitar opción'));
    await tester.pumpAndSettle();

    final variants = await save(tester);
    expect(variants, hasLength(1));
    expect(variants.single['id'], 'v8');
    expect(variants.single['name'], 'Default');
    expect(variants.single['options'], isEmpty);
  });
}
