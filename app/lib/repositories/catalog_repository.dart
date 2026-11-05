import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../models/shop_settings.dart';
import 'api_client.dart';

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
  /// sub-categories) by slug. An unknown category has no products.
  Future<List<Product>> fetchProducts({
    String? categorySlug,
    bool featuredOnly = false,
  }) async {
    try {
      final json = await _api.get(
        '/api/products',
        query: {
          'category': ?categorySlug,
          if (featuredOnly) 'featured': 'true',
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

/// Products of a category, including those of its sub-categories.
final categoryProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  slug,
) {
  return ref.watch(catalogRepositoryProvider).fetchProducts(categorySlug: slug);
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
