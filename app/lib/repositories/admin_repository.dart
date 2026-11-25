import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../models/category.dart';
import '../models/costs.dart';
import '../models/coupon.dart';
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
    this.costCents,
  }) : options = options ?? {};

  factory VariantDraft.fromVariant(ProductVariant v) => VariantDraft(
    id: v.id,
    name: v.name,
    sku: v.sku ?? '',
    options: Map.of(v.options),
    priceCents: v.priceCents,
    stock: v.stock,
    isActive: v.isActive,
    costCents: v.costCents,
  );

  /// `null` for variants that don't exist in the database yet.
  final String? id;
  String name;
  String sku;
  Map<String, String> options;
  int? priceCents;
  int? stock;
  bool isActive;

  /// Its own cost; `null` = the product's.
  int? costCents;

  /// Variant payload for the admin API. Its position is its index in the list.
  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'sku': sku.trim().isEmpty ? null : sku.trim(),
    'options': options,
    'price_cents': priceCents,
    'stock': stock,
    'is_active': isActive,
    'cost_cents': costCents,
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

  /// Price of each box size.
  Future<CostSettings> fetchCostSettings() async =>
      CostSettings.fromJson(await _api.get('/api/admin/cost-settings'));

  Future<CostSettings> saveCostSettings(CostSettings settings) async =>
      CostSettings.fromJson(
        await _api.put('/api/admin/cost-settings', settings.toJson()),
      );

  Future<List<Supplier>> fetchSuppliers() async =>
      parseList(await _api.get('/api/admin/suppliers'), Supplier.fromJson);

  /// Creates the supplier (no id) or updates it.
  Future<Supplier> saveSupplier(Supplier supplier) async => Supplier.fromJson(
    supplier.id == null
        ? await _api.post('/api/admin/suppliers', supplier.toJson())
        : await _api.put(
            '/api/admin/suppliers/${supplier.id}',
            supplier.toJson(),
          ),
  );

  /// Its products are left without a supplier; past orders keep its name.
  Future<void> deleteSupplier(String supplierId) async {
    await _api.delete('/api/admin/suppliers/$supplierId');
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

  /// Every coupon, newest first, with its status today and its uses.
  Future<List<Coupon>> fetchCoupons() async =>
      parseList(await _api.get('/api/admin/coupons'), Coupon.fromJson);

  /// Creates the coupon (when [couponId] is null) or updates it. Refused
  /// (409, `coupon_code_taken`) when another coupon has the same code.
  Future<Coupon> saveCoupon(Coupon coupon, {String? couponId}) async {
    final json = couponId == null
        ? await _api.post('/api/admin/coupons', coupon.toJson())
        : await _api.put('/api/admin/coupons/$couponId', coupon.toJson());
    return Coupon.fromJson(json as Map<String, dynamic>);
  }

  Future<Coupon> setCouponActive(String couponId, bool isActive) async =>
      Coupon.fromJson(
        await _api.patch('/api/admin/coupons/$couponId', {
              'is_active': isActive,
            })
            as Map<String, dynamic>,
      );

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

/// Products with something sold at no cost (see [Product.missingCost]): the
/// orders' costs and profit leave it out. The admin shows a warning while
/// there are any.
final productsWithoutCostProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(adminProductsProvider.future);
  return products.where((p) => p.missingCost).toList();
});

final adminCategoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchAllCategories();
});

final costSettingsProvider = FutureProvider<CostSettings>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchCostSettings();
});

final suppliersProvider = FutureProvider<List<Supplier>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchSuppliers();
});

final adminCouponsProvider = FutureProvider<List<Coupon>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchCoupons();
});

final adminProductProvider = FutureProvider.autoDispose
    .family<Product?, String>((ref, id) {
      return ref.watch(adminRepositoryProvider).fetchProduct(id);
    });
