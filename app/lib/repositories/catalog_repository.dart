import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../models/shop_settings.dart';
import 'api_client.dart';

/// How product lists are ordered. [apiValue] goes to `/api/products?sort=`,
/// [urlValue] to the page address (`/c/navidad?orden=nombre`).
enum ProductSort {
  price('price', 'precio', 'Precio: de menor a mayor'),
  priceDesc('price_desc', 'precio-desc', 'Precio: de mayor a menor'),
  name('name', 'nombre', 'Nombre (A–Z)');

  const ProductSort(this.apiValue, this.urlValue, this.label);

  final String apiValue;
  final String urlValue;
  final String label;

  /// The default: cheapest first.
  static const standard = ProductSort.price;

  /// From the `orden` URL parameter; unknown values fall back to the default.
  static ProductSort fromUrl(String? value) => ProductSort.values.firstWhere(
    (sort) => sort.urlValue == value,
    orElse: () => standard,
  );
}

/// Read-only access to the public storefront catalog through the API
/// (`/api/categories`, `/api/products`, `/api/settings`). Only active items
/// are returned; admins use `/api/admin/*` for everything else.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  /// Active categories in menu order.
  Future<List<Category>> fetchCategories() async =>
      parseList(await _api.get('/api/categories'), Category.fromJson);

  /// Featured products, or the products of a category (and its
  /// sub-categories) by slug, in [sort] order. An unknown category has no
  /// products.
  /// [search] keeps the products whose name or description has every word of
  /// it (accents and case don't matter); name matches come first.
  Future<List<Product>> fetchProducts({
    String? categorySlug,
    bool featuredOnly = false,
    String? search,
    ProductSort sort = ProductSort.standard,
  }) async {
    try {
      final json = await _api.get(
        '/api/products',
        query: {
          'category': ?categorySlug,
          if (featuredOnly) 'featured': 'true',
          if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
          'sort': sort.apiValue,
        },
      );
      return parseList(json, Product.fromJson);
    } on ApiException catch (error) {
      if (categorySlug != null && error.statusCode == 404) return [];
      rethrow;
    }
  }

  Future<Product?> fetchProductBySlug(String slug) async {
    try {
      return Product.fromJson(
        await _api.get('/api/products/${Uri.encodeComponent(slug)}'),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ShopSettings> fetchSettings() async =>
      ShopSettings.fromJson(await _api.get('/api/settings'));
}

final catalogRepositoryProvider = Provider(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(catalogRepositoryProvider).fetchCategories();
});

final categoryTreeProvider = FutureProvider<List<CategoryNode>>((ref) async {
  final categories = await ref.watch(categoriesProvider.future);
  return CategoryNode.buildTree(categories.where((c) => c.isActive).toList());
});

final featuredProductsProvider = FutureProvider<List<Product>>((ref) {
  return ref.watch(catalogRepositoryProvider).fetchProducts(featuredOnly: true);
});

/// Products of a category, including those of its sub-categories, in the
/// chosen order.
final categoryProductsProvider =
    FutureProvider.family<List<Product>, ({String slug, ProductSort sort})>((
      ref,
      key,
    ) {
      return ref
          .watch(catalogRepositoryProvider)
          .fetchProducts(categorySlug: key.slug, sort: key.sort);
    });

/// Products whose name or description matches the search text (empty text:
/// none).
final searchProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) async {
  if (query.trim().length < 2) return const [];
  return ref.watch(catalogRepositoryProvider).fetchProducts(search: query);
});

final productBySlugProvider = FutureProvider.family<Product?, String>((
  ref,
  slug,
) {
  return ref.watch(catalogRepositoryProvider).fetchProductBySlug(slug);
});

final shopSettingsProvider = FutureProvider<ShopSettings>((ref) {
  return ref.watch(catalogRepositoryProvider).fetchSettings();
});
