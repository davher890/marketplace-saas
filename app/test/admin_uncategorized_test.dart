import 'package:dona_galleta/features/admin/admin_products_screen.dart';
import 'package:dona_galleta/features/admin/admin_shell.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/repositories/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Remembers closed warnings in memory instead of the device's storage.
class _MemoryStore extends DismissedWarningsStore {
  _MemoryStore([Map<String, Set<String>>? stored]) : stored = stored ?? {};

  Map<String, Set<String>> stored;

  @override
  Future<Map<String, Set<String>>> load() async => stored;

  @override
  Future<void> save(Map<String, Set<String>> dismissed) async =>
      stored = dismissed;
}

Product _product(String name, List<String> categories, {bool photo = true}) =>
    Product.fromJson({
      'id': name,
      'name': name,
      'slug': name.toLowerCase(),
      'base_price_cents': 1000,
      'category_ids': categories,
      'product_variants': [],
      'product_images': [
        if (photo)
          {
            'id': 'i-$name',
            'product_id': name,
            'url': 'https://img.test/$name.jpg',
          },
      ],
    });

void main() {
  Future<GoRouter> pumpAdmin(
    WidgetTester tester,
    List<Product> products, {
    String location = '/admin/orders',
    DismissedWarningsStore? store,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        ShellRoute(
          builder: (_, _, child) => AdminShell(child: child),
          routes: [
            GoRoute(
              path: '/admin/orders',
              builder: (_, _) => const Text('Pedidos'),
            ),
            GoRoute(
              path: '/admin/products',
              builder: (_, state) => AdminProductsScreen(
                onlyUncategorized:
                    state.uri.queryParameters['sin_categoria'] == '1',
                onlyWithoutPhoto: state.uri.queryParameters['sin_foto'] == '1',
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminProductsProvider.overrideWith((ref) async => products),
          adminCategoriesProvider.overrideWith((ref) async => []),
          dismissedWarningsStoreProvider.overrideWithValue(
            store ?? _MemoryStore(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  final mixed = [
    _product('Taza', ['c1']),
    _product('Body', []),
    _product('Gorro', []),
  ];

  testWidgets('warns when some product has no category', (tester) async {
    await pumpAdmin(tester, mixed);
    expect(
      find.textContaining('Hay 2 productos sin categoría (Body, Gorro)'),
      findsOneWidget,
    );
  });

  testWidgets('no warnings when every product has category and photo', (
    tester,
  ) async {
    await pumpAdmin(tester, [
      _product('Taza', ['c1']),
    ]);
    expect(find.textContaining('sin categoría'), findsNothing);
    expect(find.textContaining('sin foto'), findsNothing);
  });

  testWidgets('warns about products without photo, and lists them', (
    tester,
  ) async {
    final router = await pumpAdmin(tester, [
      _product('Taza', ['c1']),
      _product('Body', ['c1'], photo: false),
    ]);
    expect(
      find.text(
        'Hay 1 producto sin foto (Body): se ve en la tienda sin imagen.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('sin categoría'), findsNothing);

    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/admin/products?sin_foto=1');
    expect(find.text('Taza'), findsNothing);
    expect(find.text('Body'), findsWidgets);
  });

  testWidgets('both warnings at once, and both filters together', (
    tester,
  ) async {
    final router = await pumpAdmin(tester, [
      _product('Taza', ['c1']),
      _product('Body', [], photo: false),
      _product('Gorro', []),
    ], location: '/admin/products?sin_categoria=1');
    expect(find.textContaining('sin categoría'), findsWidgets);
    expect(find.textContaining('sin foto (Body)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Sin foto (1)'));
    await tester.pumpAndSettle();
    expect(
      router.state.uri.toString(),
      '/admin/products?sin_categoria=1&sin_foto=1',
    );
    expect(find.text('Gorro'), findsNothing);
    expect(find.text('Body'), findsWidgets);
  });

  testWidgets('a warning closes with its X and the choice is saved', (
    tester,
  ) async {
    final store = _MemoryStore();
    await pumpAdmin(tester, [_product('Body', [], photo: false)], store: store);
    expect(find.textContaining('sin foto (Body)'), findsOneWidget);
    expect(find.byTooltip('Cerrar aviso'), findsNWidgets(2));

    // Close the photo warning only.
    final photoWarning = find.ancestor(
      of: find.textContaining('sin foto'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: photoWarning.first,
        matching: find.byTooltip('Cerrar aviso'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('sin foto'), findsNothing);
    expect(find.textContaining('sin categoría (Body)'), findsOneWidget);
    expect(store.stored, {
      'without_photo': {'Body'},
    });
  });

  final closedForBody = {
    'without_photo': {'Body'},
  };

  testWidgets('a closed warning stays hidden for the same products', (
    tester,
  ) async {
    await pumpAdmin(tester, [
      _product('Taza', ['c1']),
      _product('Body', ['c1'], photo: false),
    ], store: _MemoryStore(closedForBody));
    expect(find.textContaining('sin foto'), findsNothing);
  });

  testWidgets('a closed warning shows again when another product joins it', (
    tester,
  ) async {
    await pumpAdmin(tester, [
      _product('Body', ['c1'], photo: false),
      _product('Gorro', ['c1'], photo: false),
    ], store: _MemoryStore(closedForBody));
    expect(find.textContaining('Hay 2 productos sin foto'), findsOneWidget);
  });

  testWidgets('"Revisar" lists only the products without category', (
    tester,
  ) async {
    final router = await pumpAdmin(tester, mixed);
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/admin/products?sin_categoria=1');
    expect(find.text('Body'), findsWidgets);
    expect(find.text('Gorro'), findsWidgets);
    expect(find.text('Taza'), findsNothing);

    // Turning the filter off shows everything again.
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/admin/products');
    expect(find.text('Taza'), findsOneWidget);
  });
}
