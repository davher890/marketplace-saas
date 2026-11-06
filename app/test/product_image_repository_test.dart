import 'dart:convert';
import 'dart:typed_data';

import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/product_image_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<http.Request> requests;

  /// The API (shop.test) and Supabase Storage (storage.test), both mocked.
  ProductImageRepository repository({int storageStatus = 200}) {
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'storage.test') {
        return http.Response(
          storageStatus < 300
              ? jsonEncode({'Key': 'product-images/p1/123-abc.png'})
              : jsonEncode({
                  'statusCode': '$storageStatus',
                  'error': 'Denied',
                  'message': 'Denied',
                }),
          storageStatus,
        );
      }
      if (request.url.path.endsWith('/upload-url')) {
        return http.Response(
          jsonEncode({
            'bucket': 'product-images',
            'path': 'p1/123-abc.png',
            'token': 'signed-token',
            'content_type': 'image/png',
          }),
          200,
        );
      }
      return http.Response('{}', 201);
    });
    return ProductImageRepository(
      ApiClient(baseUrl: 'https://shop.test', httpClient: client),
      supabase: SupabaseClient(
        'https://storage.test',
        'publishable-key',
        httpClient: client,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
  }

  final bytes = Uint8List.fromList([1, 2, 3]);

  test(
    'uploads with the signed upload from the API, then registers it',
    () async {
      await repository().upload(
        productId: 'p1',
        bytes: bytes,
        fileName: 'foto.png',
      );

      expect(requests.map((r) => '${r.method} ${r.url.host}${r.url.path}'), [
        'POST shop.test/api/admin/products/p1/images/upload-url',
        'PUT storage.test/storage/v1/object/upload/sign/product-images/p1/123-abc.png',
        'POST shop.test/api/admin/products/p1/images',
      ]);
      expect(jsonDecode(requests[0].body), {'file_name': 'foto.png'});
      expect(requests[1].url.queryParameters['token'], 'signed-token');
      // The Dart SDK sends the file as a multipart form with its type.
      expect(
        requests[1].headers['content-type'],
        startsWith('multipart/form-data'),
      );
      final form = latin1.decode(requests[1].bodyBytes);
      expect(form, contains('content-type: image/png'));
      expect(form, contains(latin1.decode(bytes)));
      expect(jsonDecode(requests[2].body), {'storage_path': 'p1/123-abc.png'});
    },
  );

  test('a failed upload is reported and not registered', () async {
    final repo = repository(storageStatus: 403);
    await expectLater(
      repo.upload(productId: 'p1', bytes: bytes, fileName: 'foto.png'),
      throwsA(isA<ApiException>()),
    );
    expect(requests, hasLength(2));
  });
}
