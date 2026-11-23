import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/auth.dart';
import '../core/env.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable reason sent by the API (e.g. `invalid_credentials`).
  final String? code;

  @override
  String toString() => message;
}

/// Gives the [ApiClient] the access token to send (see `AuthController`).
abstract class TokenSource {
  /// Current access token, renewed first if it's about to expire.
  Future<String?> accessToken();

  /// Renews the token after the API rejected it. Null if that's not possible.
  Future<String?> refreshedAccessToken();
}

/// Client for the Vercel API (`/api/*`), where all the business logic lives.
/// Sends the session's access token so the API knows who is calling.
class ApiClient {
  ApiClient({this._tokens, http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  final TokenSource? _tokens;
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

  /// [bearer] sends that token instead of the session's (e.g. signing out a
  /// session that is no longer the current one).
  Future<dynamic> post(String path, [Object? body, String? bearer]) =>
      _send('POST', path, body: body, bearer: bearer);

  Future<dynamic> put(String path, Object? body) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, Object? body) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, [Object? body]) =>
      _send('DELETE', path, body: body);

  /// GET of a file (e.g. a CSV export): its raw bytes.
  Future<Uint8List> getBytes(String path, {Map<String, String>? query}) async {
    final response = await _execute('GET', path, query: query);
    _throwIfError(response);
    return response.bodyBytes;
  }

  /// Sends the request and returns the decoded JSON body (`null` for 204).
  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? bearer,
  }) async {
    final response = await _execute(
      method,
      path,
      body: body,
      query: query,
      bearer: bearer,
    );
    _throwIfError(response);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  /// Sends the request with the session's token. After a 401 it renews the
  /// session once and tries again.
  Future<http.Response> _execute(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? bearer,
  }) async {
    final token = bearer ?? await _tokens?.accessToken();
    var response = await _request(method, path, body, query, token);

    if (response.statusCode == 401 && bearer == null && token != null) {
      final renewed = await _tokens?.refreshedAccessToken();
      if (renewed != null) {
        response = await _request(method, path, body, query, renewed);
      }
    }
    return response;
  }

  /// Turns an error response (`{"error": ..., "code": ...}`) into an
  /// [ApiException].
  void _throwIfError(http.Response response) {
    if (response.statusCode < 400) return;
    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final error = decoded is Map ? decoded['error'] as String? : null;
    throw ApiException(
      error ?? 'Unexpected error (${response.statusCode})',
      statusCode: response.statusCode,
      code: decoded is Map ? decoded['code'] as String? : null,
    );
  }

  Future<http.Response> _request(
    String method,
    String path,
    Object? body,
    Map<String, String>? query,
    String? token,
  ) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);
    return http.Response.fromStream(await _http.send(request));
  }
}

/// The API as the signed-in user (or anonymously when signed out).
final apiClientProvider = Provider(
  (ref) => ApiClient(tokens: ref.read(authProvider.notifier)),
);

/// Casts a decoded JSON list into typed models.
List<T> parseList<T>(dynamic json, T Function(Map<String, dynamic>) fromJson) =>
    (json as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
