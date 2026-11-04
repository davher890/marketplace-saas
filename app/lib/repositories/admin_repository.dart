import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/providers.dart';
import '../models/product.dart';
import '../models/shop_settings.dart';

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
}

/// Write operations for the admin panel. Every call is authorized by RLS
/// (`is_admin()`), so a non-admin user simply gets a permission error.
class AdminRepository {
  AdminRepository(this._db);

  final SupabaseClient _db;

  static const imagesBucket = 'product-images';

  Future<List<Product>> fetchAllProducts() async {
    final rows = await _db
        .from('products')
        .select(Product.selectQuery)
        .order('updated_at', ascending: false);
    return rows.map(Product.fromJson).toList();
  }

  /// Creates or updates a product and syncs its variants.
  /// Returns the product id.
  Future<String> saveProduct({
    String? productId,
    required Map<String, dynamic> productRow,
    required List<VariantDraft> variants,
  }) async {
    final String id;
    if (productId == null) {
      final inserted = await _db
          .from('products')
          .insert(productRow)
          .select('id')
          .single();
      id = inserted['id'] as String;
    } else {
      await _db.from('products').update(productRow).eq('id', productId);
      id = productId;
    }

    // Variants removed in the form are deleted; the rest are upserted.
    final keptIds = variants.map((v) => v.id).whereType<String>().toList();
    var delete = _db.from('product_variants').delete().eq('product_id', id);
    if (keptIds.isNotEmpty) {
      delete = delete.not('id', 'in', '(${keptIds.join(',')})');
    }
    await delete;

    for (final (index, draft) in variants.indexed) {
      final row = ProductVariant(
        id: draft.id ?? '',
        productId: id,
        name: draft.name.trim().isEmpty ? 'Default' : draft.name.trim(),
        sku: draft.sku,
        options: draft.options,
        priceCents: draft.priceCents,
        stock: draft.stock,
        position: index,
        isActive: draft.isActive,
      ).toRow();

      if (draft.id == null) {
        await _db.from('product_variants').insert(row);
      } else {
        await _db.from('product_variants').update(row).eq('id', draft.id!);
      }
    }
    return id;
  }

  Future<void> deleteProduct(String productId) async {
    final images = await _db
        .from('product_images')
        .select('storage_path')
        .eq('product_id', productId);
    final paths = images
        .map((row) => row['storage_path'] as String?)
        .whereType<String>()
        .toList();
    if (paths.isNotEmpty) await _db.storage.from(imagesBucket).remove(paths);
    await _db.from('products').delete().eq('id', productId);
  }

  Future<void> setProductActive(String productId, bool isActive) async {
    await _db
        .from('products')
        .update({'is_active': isActive})
        .eq('id', productId);
  }

  /// Uploads an image to Storage and links it to the product.
  Future<void> uploadProductImage({
    required String productId,
    required Uint8List bytes,
    required String fileName,
    required int position,
  }) async {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'jpg';
    final path =
        '$productId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _db.storage
        .from(imagesBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: 'image/$extension',
            upsert: false,
          ),
        );
    final url = _db.storage.from(imagesBucket).getPublicUrl(path);
    await _db.from('product_images').insert({
      'product_id': productId,
      'url': url,
      'storage_path': path,
      'position': position,
    });
  }

  /// Links an externally hosted image (e.g. migrated from Wix).
  Future<void> addProductImageUrl({
    required String productId,
    required String url,
    required int position,
  }) async {
    await _db.from('product_images').insert({
      'product_id': productId,
      'url': url,
      'position': position,
    });
  }

  Future<void> deleteProductImage(ProductImage image) async {
    if (image.storagePath != null) {
      await _db.storage.from(imagesBucket).remove([image.storagePath!]);
    }
    await _db.from('product_images').delete().eq('id', image.id);
  }

  Future<void> saveSettings(ShopSettings settings) async {
    await _db.from('shop_settings').update(settings.toRow()).eq('id', true);
  }
}

final adminRepositoryProvider = Provider(
  (ref) => AdminRepository(ref.watch(supabaseProvider)),
);

final adminProductsProvider = FutureProvider<List<Product>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(adminRepositoryProvider).fetchAllProducts();
});
