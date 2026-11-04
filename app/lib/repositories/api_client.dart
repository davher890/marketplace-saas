import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../core/providers.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin client for the Vercel serverless API (`/api/*`).
/// Sends the Supabase access token so the API acts on behalf of the user.
class ApiClient {
  ApiClient(this._db, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final SupabaseClient _db;
  final http.Client _http;

  Uri _uri(String path) {
    if (Env.apiBaseUrl.isNotEmpty) return Uri.parse('${Env.apiBaseUrl}$path');
    if (kIsWeb) return Uri.base.resolve(path); // Same origin as the web app.
    throw const ApiException('API_BASE_URL is not configured');
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = _db.auth.currentSession?.accessToken;
    final response = await _http.post(
      _uri(path),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw ApiException(
        decoded['error'] as String? ??
            'Unexpected error (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}

final apiClientProvider = Provider(
  (ref) => ApiClient(ref.watch(supabaseProvider)),
);
