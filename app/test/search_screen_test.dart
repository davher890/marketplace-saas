import 'package:dona_galleta/features/catalog/search_screen.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late List<String> searched;

  Future<GoRouter> pumpSearch(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    searched = [];
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/buscar',
          builder: (_, state) => Scaffold(
            body: SingleChildScrollView(
              child: SearchScreen(query: state.uri.queryParameters['q'] ?? ''),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchProductsProvider.overrideWith((ref, query) async {
            searched.add(query);
            return query == 'bola'
                ? [
                    Product.fromJson(const {
                      'id': 'p1',
                      'name': 'Bola de madera',
                      'slug': 'bola-de-madera',
                      'base_price_cents': 1100,
                      'product_variants': [],
                      'product_images': [],
                    }),
                  ]
                : <Product>[];
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('typing searches and keeps the text in the URL', (tester) async {
    final router = await pumpSearch(tester, '/buscar');
    expect(find.text('Escribe al menos dos letras.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bola');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/buscar?q=bola');
    expect(searched, ['bola']);
    expect(find.text('Bola de madera'), findsOneWidget);
  });

  testWidgets('says so when nothing matches', (tester) async {
    await pumpSearch(tester, '/buscar?q=xyz');
    expect(
      find.text('No hay productos que coincidan con "xyz".'),
      findsOneWidget,
    );
  });
}
