import 'dart:convert';

import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final requests = <Uri>[];

  /// Answers like the API: 404 for unknown slugs, a product otherwise.
  CatalogRepository repository() => CatalogRepository(
    ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        requests.add(request.url);
        final path = request.url.path;
        final body = switch (path) {
          '/api/products/unknown' => {'error': 'Product not found'},
          '/api/products'
              when request.url.queryParameters['category'] == 'nope' =>
            {'error': 'Category not found'},
          '/api/products/cojin-nube' => _product,
          '/api/products' => [_product],
          '/api/categories' => [
            {'id': 'c1', 'name': 'Bebé', 'slug': 'bebe'},
          ],
          '/api/settings' => {'shipping_flat_cents': 495},
          _ => {'error': 'Not found'},
        };
        final status = body is Map && body.containsKey('error') ? 404 : 200;
        return http.Response(jsonEncode(body), status);
      }),
    ),
  );

  setUp(requests.clear);

  test('reads the catalog from the API, never from Supabase REST', () async {
    final repo = repository();
    expect((await repo.fetchCategories()).single.slug, 'bebe');
    expect(
      (await repo.fetchProducts(featuredOnly: true)).single.name,
      'Cojín nube',
    );
    expect((await repo.fetchProducts(categorySlug: 'bebe')), hasLength(1));
    expect((await repo.fetchProductBySlug('cojin-nube'))?.slug, 'cojin-nube');
    expect((await repo.fetchSettings()).shippingFlatCents, 495);

    expect(requests.map((u) => u.toString()), [
      'https://shop.test/api/categories',
      'https://shop.test/api/products?featured=true',
      'https://shop.test/api/products?category=bebe',
      'https://shop.test/api/products/cojin-nube',
      'https://shop.test/api/settings',
    ]);
  });

  test('unknown product or category is empty, not an error', () async {
    final repo = repository();
    expect(await repo.fetchProductBySlug('unknown'), isNull);
    expect(await repo.fetchProducts(categorySlug: 'nope'), isEmpty);
  });
}

const _product = {
  'id': 'p1',
  'name': 'Cojín nube',
  'slug': 'cojin-nube',
  'base_price_cents': 1695,
  'product_variants': [],
  'product_images': [],
};
