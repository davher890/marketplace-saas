import 'package:dona_galleta/features/catalog/category_screen.dart';
import 'package:dona_galleta/models/category.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late List<({String slug, ProductSort sort})> loaded;

  Future<GoRouter> pumpCategory(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    loaded = [];
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/c/:slug',
          builder: (_, state) => Scaffold(
            body: SingleChildScrollView(
              child: CategoryScreen(
                slug: state.pathParameters['slug']!,
                sort: ProductSort.fromUrl(state.uri.queryParameters['orden']),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) async => const [
              Category(id: 'c1', name: 'Navidad', slug: 'navidad'),
            ],
          ),
          categoryProductsProvider.overrideWith((ref, key) async {
            loaded.add(key);
            return <Product>[];
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('lists the cheapest first by default', (tester) async {
    await pumpCategory(tester, '/c/navidad');
    expect(loaded.last, (slug: 'navidad', sort: ProductSort.price));
    expect(find.text('Precio: de menor a mayor'), findsWidgets);
  });

  testWidgets(
    'choosing "Nombre" reloads in that order and keeps it in the URL',
    (tester) async {
      final router = await pumpCategory(tester, '/c/navidad');
      await tester.tap(find.byType(DropdownMenu<ProductSort>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nombre (A–Z)').last);
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/c/navidad?orden=nombre');
      expect(loaded.last, (slug: 'navidad', sort: ProductSort.name));
    },
  );

  testWidgets('the order in the URL is kept when opening the page', (
    tester,
  ) async {
    await pumpCategory(tester, '/c/navidad?orden=precio-desc');
    expect(loaded.last, (slug: 'navidad', sort: ProductSort.priceDesc));
    expect(find.text('Precio: de mayor a menor'), findsWidgets);
  });
}
