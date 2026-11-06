import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import 'api_client.dart';

/// Everything the app does with product image files: uploading, linking and
/// deleting them. Displaying them only needs the `url` the API returns.
///
/// This is the only file in the app that uses the Supabase SDK (and its
/// configuration): the file goes straight to Supabase Storage with a one-time
/// upload the API signs (`server/services/images.ts`). Switching storage
/// providers means changing this file and that one.
class ProductImageRepository {
  ProductImageRepository(this._api, {SupabaseClient? supabase})
    : _client = supabase;

  final ApiClient _api;
  SupabaseClient? _client;

  /// Built on first use: only admins upload images.
  SupabaseClient get _supabase => _client ??= _createClient();

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static SupabaseClient _createClient() {
    if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
      throw const ApiException(
        'Para subir imágenes, la app necesita SUPABASE_URL y '
        'SUPABASE_PUBLISHABLE_KEY (ver README).',
      );
    }
    // Only Storage is used: sessions are handled by the API (core/auth.dart).
    return SupabaseClient(
      _supabaseUrl,
      _supabaseKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  /// Uploads the file straight to storage (it doesn't go through the API),
  /// then adds it to the product's images.
  Future<void> upload({
    required String productId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final target =
        await _api.post('/api/admin/products/$productId/images/upload-url', {
              'file_name': fileName,
            })
            as Map<String, dynamic>;
    final path = target['path'] as String;

    try {
      await _supabase.storage
          .from(target['bucket'] as String)
          .uploadBinaryToSignedUrl(
            path,
            target['token'] as String,
            bytes,
            FileOptions(contentType: target['content_type'] as String),
          );
    } on StorageException catch (error) {
      // The rest of the app only knows ApiException.
      throw ApiException(
        'No se pudo subir la imagen: ${error.message}',
        statusCode: int.tryParse(error.statusCode ?? ''),
      );
    }

    await _api.post('/api/admin/products/$productId/images', {
      'storage_path': path,
    });
  }

  /// Links an externally hosted image (e.g. migrated from Wix).
  Future<void> addUrl({required String productId, required String url}) =>
      _api.post('/api/admin/products/$productId/images', {'url': url});

  /// Removes the image from the product and deletes its stored file.
  Future<void> delete(ProductImage image) =>
      _api.delete('/api/admin/images/${image.id}');
}

final productImageRepositoryProvider = Provider(
  (ref) => ProductImageRepository(ref.watch(apiClientProvider)),
);
