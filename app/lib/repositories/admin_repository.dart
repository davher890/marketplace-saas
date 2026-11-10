import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/shop_settings.dart';
import 'api_client.dart';

/// Editable variant used by the product form before it is persisted.
class VariantDraft {
  VariantDraft({
    this.id,
    this.name = 'Default',
    this.sku = '',
    Map<String, String>? options,
    this.priceCents,
    this.stock,
    this.isActive = true,
  }) : options = options ?? {};

  factory VariantDraft.fromVariant(ProductVariant v) => VariantDraft(
    id: v.id,
    name: v.name,
    sku: v.sku ?? '',
    options: Map.of(v.options),
    priceCents: v.priceCents,
    stock: v.stock,
    isActive: v.isActive,
  );

  /// `null` for variants that don't exist in the database yet.
  final String? id;
  String name;
  String sku;
  Map<String, String> options;
  int? priceCents;
  int? stock;
  bool isActive;

  /// Variant payload for the admin API. Its position is its index in the list.
  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'sku': sku.trim().isEmpty ? null : sku.trim(),
    'options': options,
    'price_cents': priceCents,
    'stock': stock,
    'is_active': isActive,
  };
}

/// Admin operations. The API checks the admin role on every call.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<List<Product>> fetchAllProducts() async =>
      parseList(await _api.get('/api/admin/products'), Product.fromJson);

  Future<Product?> fetchProduct(String id) async {
    try {
      return Product.fromJson(await _api.get('/api/admin/products/$id'));
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Every category, including inactive ones.
  Future<List<Category>> fetchAllCategories() async =>
      parseList(await _api.get('/api/admin/categories'), Category.fromJson);

  /// Creates the category (when [categoryId] is null) or updates it.
  Future<Category> saveCategory({
    String? categoryId,
    required String name,
    required String slug,
    String? parentId,
    String? description,
    bool isActive = true,
  }) async {
    final body = {
      'name': name,
      'slug': slug,
      'parent_id': parentId,
      'description': description,
      'is_active': isActive,
    };
    final json = categoryId == null
        ? await _api.post('/api/admin/categories', body)
        : await _api.put('/api/admin/categories/$categoryId', body);
    return Category.fromJson(json);
  }

  Future<void> setCategoryActive(String categoryId, bool isActive) async {
    await _api.patch('/api/admin/categories/$categoryId', {
      'is_active': isActive,
    });
  }

  /// Moves the category one place up or down among its siblings.
  Future<void> moveCategory(String categoryId, {required bool up}) async {
    await _api.post('/api/admin/categories/$categoryId/move', {
      'direction': up ? 'up' : 'down',
    });
  }

  /// Refused by the API (409) while the category has products or sub-categories.
  Future<void> deleteCategory(String categoryId) async {
    await _api.delete('/api/admin/categories/$categoryId');
  }

  /// Creates the product (when [productId] is null) or updates it. The API
  /// syncs the variants in the same transaction. Returns the saved product.
  Future<Product> saveProduct({
    String? productId,
    required Map<String, dynamic> product,
    required List<VariantDraft> variants,
  }) async {
    final body = {
      ...product,
      'variants': variants.map((v) => v.toJson()).toList(),
    };
    final json = productId == null
        ? await _api.post('/api/admin/products', body)
        : await _api.put('/api/admin/products/$productId', body);
    return Product.fromJson(json);
  }

  Future<void> setProductActive(String productId, bool isActive) async {
    await _api.patch('/api/admin/products/$productId', {'is_active': isActive});
  }

  /// Copies the product (hidden, "(copia)" in the name, variants without
  /// SKU, its own copy of each photo) and returns the copy.
  Future<Product> duplicateProduct(String productId) async => Product.fromJson(
    await _api.post('/api/admin/products/$productId/duplicate')
        as Map<String, dynamic>,
  );

  Future<void> deleteProduct(String productId) async {
    await _api.delete('/api/admin/products/$productId');
  }

  Future<ShopSettings> saveSettings(ShopSettings settings) async =>
      ShopSettings.fromJson(
        await _api.put('/api/admin/settings', settings.toJson()),
      );
}

final adminRepositoryProvider = Provider(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

final adminProductsProvider = FutureProvider<List<Product>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchAllProducts();
});

/// Products in no category: they don't appear in any menu of the shop (only
/// in search, if active). The admin shows a warning while there are any.
final uncategorizedProductsProvider = FutureProvider<List<Product>>((
  ref,
) async {
  final products = await ref.watch(adminProductsProvider.future);
  return products.where((p) => p.categoryIds.isEmpty).toList();
});

/// Products with no photo: the shop shows them with an empty card. The
/// admin shows a warning while there are any.
final productsWithoutPhotoProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(adminProductsProvider.future);
  return products.where((p) => p.images.isEmpty).toList();
});

final adminCategoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchAllCategories();
});

final adminProductProvider = FutureProvider.autoDispose
    .family<Product?, String>((ref, id) {
      return ref.watch(adminRepositoryProvider).fetchProduct(id);
    });
