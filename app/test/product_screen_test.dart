import 'dart:convert';

import 'package:dona_galleta/core/auth.dart';
import 'package:dona_galleta/features/catalog/product_screen.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/cart_repository.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A product with stock tracking and a "Color del lazo" choice list.
Product _product({int? stock = 3, bool customizable = true}) =>
    Product.fromJson({
      'id': 'p1',
      'name': 'Chupetero',
      'slug': 'chupetero',
      'base_price_cents': 1200,
      'is_customizable': customizable,
      'customization_label': 'Nombre a bordar',
      'choice_fields': [
        {
          'label': 'Color del lazo',
          'options': ['Rojo', 'Azul'],
        },
      ],
      'product_variants': [
        {
          'id': 'v1',
          'product_id': 'p1',
          'name': 'Default',
          'options': {},
          'stock': stock,
        },
      ],
      'product_images': [],
    });

void main() {
  late List<Map<String, dynamic>> cartBodies;

  Future<void> pumpProduct(WidgetTester tester, Product product) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cartBodies = [];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          cartBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response(
          jsonEncode({'items': [], 'item_count': 0, 'subtotal_cents': 0}),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productBySlugProvider.overrideWith((ref, slug) async => product),
          currentUserProvider.overrideWithValue(const AuthUser(id: 'u1')),
          cartRepositoryProvider.overrideWithValue(CartRepository(api)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProductScreen(slug: 'chupetero'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('customers don\'t see how many units are left', (tester) async {
    await pumpProduct(tester, _product(stock: 3));
    expect(find.textContaining('Quedan'), findsNothing);
    expect(find.textContaining('3'), findsNothing);
    expect(find.text('Hecho por encargo'), findsNothing);
  });

  testWidgets('made-to-order products still say so', (tester) async {
    await pumpProduct(tester, _product(stock: null));
    expect(find.text('Hecho por encargo'), findsOneWidget);
  });

  testWidgets('a choice must be picked, then it goes to the cart', (
    tester,
  ) async {
    await pumpProduct(tester, _product());
    await tester.enterText(find.byType(TextField).last, 'Lucía');

    await tester.tap(find.text('Añadir al carrito'));
    await tester.pumpAndSettle();
    expect(find.text('Elige: Color del lazo'), findsOneWidget);
    expect(cartBodies, isEmpty);

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Azul').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir al carrito'));
    await tester.pumpAndSettle();

    expect(cartBodies.single, {
      'variant_id': 'v1',
      'quantity': 1,
      'customization': 'Lucía',
      'choices': {'Color del lazo': 'Azul'},
    });
  });

  test('choice lists round-trip through JSON', () {
    final product = _product();
    expect(product.choiceFields.single.options, ['Rojo', 'Azul']);
    expect(product.toJson()['choice_fields'], [
      {
        'label': 'Color del lazo',
        'options': ['Rojo', 'Azul'],
      },
    ]);
  });
}
