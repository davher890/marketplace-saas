import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/providers.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/shop_settings.dart';

/// Read-only access to the public catalog. RLS hides inactive items from
/// customers, while admins see everything.
class CatalogRepository {
  CatalogRepository(this._db);

  final SupabaseClient _db;

  Future<List<Category>> fetchCategories() async {
    final rows = await _db
        .from('categories')
        .select()
        .order('position', ascending: true)
        .order('name', ascending: true);
    return rows.map(Category.fromJson).toList();
  }

  Future<Category?> fetchCategoryBySlug(String slug) async {
    final row = await _db
        .from('categories')
        .select()
        .eq('slug', slug)
        .maybeSingle();
    return row == null ? null : Category.fromJson(row);
  }

  /// Products in [categoryIds] (a category plus its sub-categories),
  /// or featured products when [featuredOnly] is set.
  Future<List<Product>> fetchProducts({
    List<String>? categoryIds,
    bool featuredOnly = false,
    bool activeOnly = true,
  }) async {
    var query = _db.from('products').select(Product.selectQuery);
    if (activeOnly) query = query.eq('is_active', true);
    if (categoryIds != null) query = query.inFilter('category_id', categoryIds);
    if (featuredOnly) query = query.eq('is_featured', true);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(Product.fromJson).toList();
  }

  Future<Product?> fetchProductBySlug(String slug) async {
    final row = await _db
        .from('products')
        .select(Product.selectQuery)
        .eq('slug', slug)
        .maybeSingle();
    return row == null ? null : Product.fromJson(row);
  }

  Future<Product?> fetchProductById(String id) async {
    final row = await _db
        .from('products')
        .select(Product.selectQuery)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Product.fromJson(row);
  }

  Future<ShopSettings> fetchSettings() async {
    final row = await _db.from('shop_settings').select().maybeSingle();
    return row == null ? ShopSettings.fallback : ShopSettings.fromJson(row);
  }
}

final catalogRepositoryProvider = Provider(
  (ref) => CatalogRepository(ref.watch(supabaseProvider)),
);

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  // Admins also see inactive categories, so refresh on auth changes.
  ref.watch(currentUserProvider);
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
) async {
  final categories = await ref.watch(categoriesProvider.future);
  final category = categories.where((c) => c.slug == slug).firstOrNull;
  if (category == null) return [];
  final ids = [
    category.id,
    ...categories.where((c) => c.parentId == category.id).map((c) => c.id),
  ];
  return ref.watch(catalogRepositoryProvider).fetchProducts(categoryIds: ids);
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
