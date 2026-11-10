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

Map<String, dynamic> _json(String id, String name) => {
  'id': id,
  'name': name,
  'slug': id,
  'base_price_cents': 1000,
  'is_active': id == 'p1',
  'category_ids': <String>[],
  'product_variants': [
    {'id': 'v-$id', 'product_id': id, 'name': 'Default', 'options': {}},
  ],
  'product_images': <Map<String, dynamic>>[],
};

void main() {
  late List<http.Request> requests;

  Future<GoRouter> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    requests = [];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(_json('p2', 'Taza (copia)')), 201);
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
            (ref, id) async => Product.fromJson(
              id == 'p1' ? _json('p1', 'Taza') : _json(id, 'Taza (copia)'),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Offset centerOf(WidgetTester tester, String tooltip) =>
      tester.getCenter(find.byTooltip(tooltip));

  testWidgets('"Duplicar" sits between "Ver en la tienda" and "Eliminar"', (
    tester,
  ) async {
    await pumpEditor(tester);
    final view = centerOf(tester, 'Ver en la tienda').dx;
    final duplicate = centerOf(tester, 'Duplicar').dx;
    final delete = centerOf(tester, 'Eliminar').dx;
    expect(view < duplicate && duplicate < delete, isTrue);
  });

  testWidgets('duplicating asks the API for a copy and opens it', (
    tester,
  ) async {
    final router = await pumpEditor(tester);
    await tester.tap(find.byTooltip('Duplicar'));
    await tester.pumpAndSettle();

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/admin/products/p1/duplicate');
    expect(router.state.uri.toString(), '/admin/products/p2');
    expect(find.textContaining('Copia creada: "Taza (copia)"'), findsOneWidget);
  });
}
