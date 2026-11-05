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

/// Client for the Vercel API (`/api/*`), where all the business logic lives.
/// Sends the Supabase access token so the API knows who is calling.
class ApiClient {
  ApiClient(this._db, {http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  final SupabaseClient _db;
  final http.Client _http;

  /// Empty on web to call the API on the app's own origin.
  final String _baseUrl;

  Uri _uri(String path, Map<String, String>? query) {
    final Uri base;
    if (_baseUrl.isNotEmpty) {
      base = Uri.parse('$_baseUrl$path');
    } else if (kIsWeb) {
      base = Uri.base.resolve(path); // Same origin as the web app.
    } else {
      throw const ApiException('API_BASE_URL is not configured');
    }
    return query == null || query.isEmpty
        ? base
        : base.replace(queryParameters: query);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, Object? body) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, Object? body) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Sends the request and returns the decoded JSON body (`null` for 204).
  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final token = _db.auth.currentSession?.accessToken;
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(await _http.send(request));
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 400) {
      final error = decoded is Map ? decoded['error'] as String? : null;
      throw ApiException(
        error ?? 'Unexpected error (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}

final apiClientProvider = Provider(
  (ref) => ApiClient(ref.watch(supabaseProvider)),
);

/// Casts a decoded JSON list into typed models.
List<T> parseList<T>(dynamic json, T Function(Map<String, dynamic>) fromJson) =>
    (json as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
